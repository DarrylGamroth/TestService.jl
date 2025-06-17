# Communication resources bundled together
mutable struct CommunicationResources
    # Aeron streams
    status_stream::Aeron.Publication
    control_stream::Aeron.Subscription
    input_streams::Vector{Aeron.Subscription}

    # Fragment handlers
    control_fragment_handler::Aeron.FragmentAssembler
    input_fragment_handler::Aeron.FragmentAssembler

    # buffer
    buf::Vector{UInt8}
end

# Main control state machine
@hsmdef mutable struct ControlStateMachine
    client::Aeron.Client
    properties::Properties
    clock::CachedEpochClock{EpochClock}
    id_gen::SnowflakeIdGenerator{CachedEpochClock{EpochClock}}
    correlation_id::Int64
    position_ptr::Base.RefValue{Int64}
    comms::Union{Nothing,CommunicationResources}
end

function ControlStateMachine(client)
    clock = CachedEpochClock(EpochClock())
    properties = Properties(clock)

    node_id = get_property(properties, :NodeId)
    id_gen = SnowflakeIdGenerator(node_id, clock)

    ControlStateMachine(
        client,
        properties,
        clock,
        id_gen,
        0,
        Ref{Int64}(0),
        nothing
    )
end

# FIXME Agent.name(sm::ControlStateMachine) = get_property(sm.properties, :Name)
Agent.name(sm::ControlStateMachine) = "TestService"

function Agent.on_start(sm::ControlStateMachine)
    @info "Starting agent $(Agent.name(sm))"

    dispatch!(sm, :Initialize)
end

function Agent.on_close(sm::ControlStateMachine)
    @info "Closing agent $(Agent.name(sm))"

    # dispatch!(sm, :Shutdown)
end

function Agent.on_error(sm::ControlStateMachine, error)
    @error "Error in agent $(Agent.name(sm)): $error" exception = (error, catch_backtrace())
end

function Agent.do_work(sm::ControlStateMachine)
    # Update the cached clock
    fetch!(sm.clock)

    work_count = 0

    work_count += input_stream_poller(sm)
    work_count += control_poller(sm)
end

function input_stream_poller(sm::ControlStateMachine)
    work_count = 0
    while true
        all_streams_empty = true
        input_fragment_handler = sm.comms.input_fragment_handler

        for subscription in sm.comms.input_streams
            fragments_read = Aeron.poll(subscription, input_fragment_handler, DEFAULT_FRAGMENT_COUNT_LIMIT)
            if fragments_read > 0
                all_streams_empty = false
            end
            work_count += fragments_read
        end
        if all_streams_empty
            break
        end
    end
    return work_count
end

function control_poller(sm::ControlStateMachine)
    Aeron.poll(sm.comms.control_stream, sm.comms.control_fragment_handler, DEFAULT_FRAGMENT_COUNT_LIMIT)
end

# Wrap control handler temporarily to measure allocations
function control_handler(sm::ControlStateMachine, buffer, header)
    # Decode the buffer as an Event message and dispatch it
    allocs = @warn_alloc 64 control_handler_func(sm, buffer, header)
    @info "Dispatched event with correlation ID $(sm.correlation_id) (allocs: $allocs)"
end

function control_handler_func(sm::ControlStateMachine, buffer, _)
    # A single buffer may contain several Event messages. Decode each one at a time and dispatch
    offset = 0
    while offset < length(buffer)
        sbe_header = MessageHeader(buffer, offset)
        message = EventMessageDecoder(buffer, offset; position_ptr=sm.position_ptr, header=sbe_header)
        header = SpidersMessageCodecs.header(message)
        sm.correlation_id = SpidersMessageCodecs.correlationId(header)
        event = SpidersMessageCodecs.key(message, Symbol)

        dispatch!(sm, event, message)

        offset += sbe_encoded_length(sbe_header) + sbe_decoded_length(message)
    end
end

function decode_message(buffer, position_ptr)
    # Decode a single message from the buffer
    message = EventMessageDecoder(buffer; position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(message)
    correlation_id = SpidersMessageCodecs.correlationId(header)
    event = SpidersMessageCodecs.key(message, Symbol)

    return message, correlation_id, event
end

function data_handler(sm::ControlStateMachine, buffer, _)
    message = TensorMessageDecoder(buffer; position_ptr=sm.position_ptr)
    header = SpidersMessageCodecs.header(message)
    sm.correlation_id = SpidersMessageCodecs.correlationId(header)
    tag = Symbol(SpidersMessageCodecs.tag(header, String))

    dispatch!(sm, tag, message)
    nothing
end

function dispatch!(sm::ControlStateMachine, event, message=nothing)
    try
        prev = Hsm.current(sm)
        Hsm.dispatch!(sm, event, message)
        current = Hsm.current(sm)

        if prev != current
            send_event_response(sm, :StateChange, current)
        end

    catch e
        if e isa AgentTerminationException
            throw(e)
        end

        @error "Error in dispatch" exception = (e, catch_backtrace())
        Hsm.dispatch!(sm, :Error, e)
    end
end

function offer(p, buf, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        result = Aeron.offer(p, buf)
        if result > 0
            return
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            continue
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            return
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        end
        attempts -= 1
    end
end

function try_claim(p, length, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        claim, result = Aeron.try_claim(p, length)
        if result > 0
            return claim
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            continue
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            return
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        end
        attempts -= 1
    end
end

# Messaging and serialization interface
@inline function send_event_response(sm::ControlStateMachine, event, value)
    response = EventMessageEncoder(sm.comms.buf; position_ptr=sm.position_ptr)
    header = SpidersMessageCodecs.header(response)

    SpidersMessageCodecs.timestampNs!(header, time_nanos(sm.clock))
    SpidersMessageCodecs.correlationId!(header, sm.correlation_id)
    SpidersMessageCodecs.tag!(header, Agent.name(sm))
    SpidersMessageCodecs.key!(response, event)
    encode(response, value)

    offer(sm.comms.status_stream, convert(AbstractArray{UInt8}, response))
end

# FIXME The SBE encoder bounds checking is incorrect so add 4 for now
@inline function send_event_response(sm::ControlStateMachine, event, value::T) where {T<:Union{AbstractString,Real,Symbol,Tuple}}
    len = sbe_encoded_length(MessageHeader) + sbe_block_length(EventMessage) + sizeof(value) + 4
    claim = try_claim(sm.comms.status_stream, len)
    if claim === nothing
        @error "Failed to claim buffer event response"
        return
    end
    response = EventMessageEncoder(buffer(claim); position_ptr=sm.position_ptr)
    header = SpidersMessageCodecs.header(response)

    SpidersMessageCodecs.timestampNs!(header, time_nanos(sm.clock))
    SpidersMessageCodecs.correlationId!(header, sm.correlation_id)
    SpidersMessageCodecs.tag!(header, Agent.name(sm))
    SpidersMessageCodecs.key!(response, event)
    encode(response, value)

    Aeron.commit(claim)
end

# Precompile statements
function _precompile_agent()
    # Core types
    precompile(Tuple{typeof(CommunicationResources)})
    precompile(Tuple{typeof(ControlStateMachine),Aeron.Client})

    # Agent interface methods
    precompile(Tuple{typeof(Agent.name),ControlStateMachine})
    precompile(Tuple{typeof(Agent.on_start),ControlStateMachine})
    precompile(Tuple{typeof(Agent.on_close),ControlStateMachine})
    precompile(Tuple{typeof(Agent.on_error),ControlStateMachine,Exception})
    precompile(Tuple{typeof(Agent.on_error),ControlStateMachine,Any})
    precompile(Tuple{typeof(Agent.do_work),ControlStateMachine})

    # Event handling and polling
    precompile(Tuple{typeof(input_stream_poller),ControlStateMachine})
    precompile(Tuple{typeof(control_poller),ControlStateMachine})
    precompile(Tuple{typeof(control_handler),ControlStateMachine,UnsafeArrays.UnsafeArray{UInt8, 1},Aeron.Header})
    precompile(Tuple{typeof(data_handler),ControlStateMachine,UnsafeArrays.UnsafeArray{UInt8, 1},Aeron.Header})

    # Dispatch methods
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol})
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol,Nothing})
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol,EventMessageDecoder})
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol,Any})

    # Communication methods
    precompile(Tuple{typeof(offer),Aeron.Publication,Vector{UInt8}})
    precompile(Tuple{typeof(offer),Aeron.Publication,Vector{UInt8},Int})
    precompile(Tuple{typeof(try_claim),Aeron.Publication,Int})
    precompile(Tuple{typeof(try_claim),Aeron.Publication,Int,Int})

    # Message sending
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,String})
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Symbol})
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Int})
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Float64})
end

# Call precompile function
_precompile_agent()
