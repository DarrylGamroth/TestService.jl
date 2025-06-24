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
    properties::Properties{CachedEpochClock{EpochClock}}
    clock::CachedEpochClock{EpochClock}
    id_gen::SnowflakeIdGenerator{CachedEpochClock{EpochClock}}
    timer_wheel::DeadlineTimerWheel
    timer_event_map::Dict{Int64, Symbol}
    correlation_id::Int64
    position_ptr::Base.RefValue{Int64}
    comms::Union{Nothing,CommunicationResources}
end

# Timer API functions
include("timers.jl")

function ControlStateMachine(client)
    clock = CachedEpochClock(EpochClock())
    now = fetch!(clock)  # Initialize the clock

    properties = Properties(clock)

    node_id = properties[:NodeId]
    id_gen = SnowflakeIdGenerator(node_id, clock)

    # Initialize the DeadleineTimerWheel 
    timer_wheel = DeadlineTimerWheel(now, 1 << 21, 1 << 9)
    
    # Preallocate timer event mapping
    timer_event_map = Dict{Int64, Symbol}()
    sizehint!(timer_event_map, 100)  # Adjust based on expected timer count

    ControlStateMachine(
        client,
        properties,
        clock,
        id_gen,
        timer_wheel,
        timer_event_map,
        0,
        Ref{Int64}(0),
        nothing
    )
end

Agent.name(sm::ControlStateMachine) = sm.properties[:Name]

function Agent.on_start(sm::ControlStateMachine)
    @info "Starting agent $(Agent.name(sm))"
end

function Agent.on_close(sm::ControlStateMachine)
    @info "Closing agent $(Agent.name(sm))"

    # dispatch!(sm, :AgentOnClose)
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
    work_count += timer_poller(sm)
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

function timer_poller(sm::ControlStateMachine)
    # Poll the timer wheel for any expired timers
    now = time_nanos(sm.clock)
    return TimerWheels.poll(timer_handler, sm.timer_wheel, now, sm)
end

# Wrap control handler temporarily to measure allocations
# function control_handler(sm::ControlStateMachine, buffer, header)
#     # Decode the buffer as an Event message and dispatch it
#     allocs = @warn_alloc 64 control_handler_func(sm, buffer, header)
#     @info "Dispatched event with correlation ID $(sm.correlation_id) (allocs: $allocs)"
# end

function control_handler(sm::ControlStateMachine, buffer, _)
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

function timer_handler(sm::ControlStateMachine, now, timer_id)
    # Look up the event for this timer
    event = get(sm.timer_event_map, timer_id, :DefaultTimer)
    
    # Clean up the mapping
    delete!(sm.timer_event_map, timer_id)
    
    # Dispatch the event
    dispatch!(sm, event, now)
    return true
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
            @info "Agent termination requested"
            throw(e)
        else
            @error "Error in dispatching event $event" exception = (e, catch_backtrace())
            Hsm.dispatch!(sm, :Error, e)
        end
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

@inline function send_event_response(sm::ControlStateMachine, event, value::AbstractArray)
    # Encode the buffer in reverse order 
    tensor = TensorMessageEncoder(sm.comms.buf; position_ptr=sm.position_ptr)
    header = SpidersMessageCodecs.header(tensor)

    SpidersMessageCodecs.timestampNs!(header, time_nanos(sm.clock))
    SpidersMessageCodecs.correlationId!(header, sm.correlation_id)
    SpidersMessageCodecs.tag!(header, Agent.name(sm))
    encode(tensor, value)
    tensor_length = sbe_encoded_length(MessageHeader) + sbe_encoded_length(tensor)
    @info "Encoded tensor length: $tensor_length, position: $(sbe_position(tensor))"
    @info "Converted tensor length: $(length(convert(AbstractArray{UInt8}, tensor)))"

    # Position is set to the end which may be incorrect, so we need to set it manually

    response = EventMessageEncoder(sm.comms.buf, sbe_position(tensor) + 4; position_ptr=sm.position_ptr)
    header = SpidersMessageCodecs.header(response)

    SpidersMessageCodecs.timestampNs!(header, time_nanos(sm.clock))
    SpidersMessageCodecs.correlationId!(header, sm.correlation_id)
    SpidersMessageCodecs.tag!(header, Agent.name(sm))
    SpidersMessageCodecs.format!(response, SpidersMessageCodecs.Format.SBE)
    SpidersMessageCodecs.key!(response, event)
    SpidersMessageCodecs.value_length!(response, tensor_length)
    # value_length doesn't increment the position, so we need to do it manually, TODO: is this correct?
    SpidersMessageCodecs.sbe_position!(response, sbe_position(response) + SpidersMessageCodecs.value_header_length(response))

    # buf = UInt8[]
    # append!(buf, convert(AbstractArray{UInt8}, response))
    # append!(buf, convert(AbstractArray{UInt8}, tensor))

    # @info "Encoded response length: $(sizeof(buf))"
    # dec = EventMessageDecoder(collect(buf))
    # println("$dec\n")

    # Offer in the correct order
    # offer(sm.comms.status_stream,
    #     (
    #         convert(AbstractArray{UInt8}, response),
    #         convert(AbstractArray{UInt8}, tensor)
    #     )
    # )
end

# @inline function send_event_response(sm::ControlStateMachine, event, value::AbstractArray)
#     # Encode the buffer in reverse order 
#     tensor = TensorMessageEncoder(sm.comms.buf; position_ptr=sm.position_ptr)
#     header = SpidersMessageCodecs.header(tensor)

#     SpidersMessageCodecs.timestampNs!(header, time_nanos(sm.clock))
#     SpidersMessageCodecs.correlationId!(header, sm.correlation_id)
#     SpidersMessageCodecs.tag!(header, Agent.name(sm))
#     encode(tensor, value)


#     response = EventMessageEncoder(sm.comms.buf, sbe_position(tensor); position_ptr=sm.position_ptr)
#     header = SpidersMessageCodecs.header(response)

#     SpidersMessageCodecs.timestampNs!(header, time_nanos(sm.clock))
#     SpidersMessageCodecs.correlationId!(header, sm.correlation_id)
#     SpidersMessageCodecs.tag!(header, Agent.name(sm))
#     SpidersMessageCodecs.key!(response, event)
#     SpidersMessageCodecs.value!(response, tensor)

#     buf = Vector{UInt8}()
#     append!(buf, convert(AbstractArray{UInt8}, response))

#     dec = EventMessageDecoder(buf)
#     println("$dec\n")

#     # Offer in the correct order
#     offer(sm.comms.status_stream,
#         (
#             convert(AbstractArray{UInt8}, response),
#             # convert(AbstractArray{UInt8}, tensor)
#         )
#     )
# end

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
    precompile(Tuple{typeof(timer_poller),ControlStateMachine})
    precompile(Tuple{typeof(control_handler),ControlStateMachine,UnsafeArrays.UnsafeArray{UInt8,1},Aeron.Header})
    precompile(Tuple{typeof(data_handler),ControlStateMachine,UnsafeArrays.UnsafeArray{UInt8,1},Aeron.Header})
    precompile(Tuple{typeof(timer_handler),ControlStateMachine,Int64,Any})

    # Message decoding
    precompile(Tuple{typeof(decode_message),UnsafeArrays.UnsafeArray{UInt8,1},Base.RefValue{Int64}})
    precompile(Tuple{typeof(decode_message),Vector{UInt8},Base.RefValue{Int64}})

    # Dispatch methods
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol})
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol,Nothing})
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol,EventMessageDecoder})
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol,TensorMessageDecoder})
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol,Int64})
    precompile(Tuple{typeof(dispatch!),ControlStateMachine,Symbol,Any})

    # Communication methods
    precompile(Tuple{typeof(offer),Aeron.Publication,Vector{UInt8}})
    precompile(Tuple{typeof(offer),Aeron.Publication,Vector{UInt8},Int})
    precompile(Tuple{typeof(try_claim),Aeron.Publication,Int})
    precompile(Tuple{typeof(try_claim),Aeron.Publication,Int,Int})

    # Timer management functions
    precompile_timers()

    # Message sending - common value types
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,String})
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Symbol})
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Int})
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Int64})
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Float64})
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Bool})

    # Common event types
    precompile(Tuple{typeof(send_event_response),ControlStateMachine,Symbol,Any})

    # Array conversions for encoders
    precompile(Tuple{typeof(convert),Type{AbstractArray{UInt8}},EventMessageEncoder})
end

# Call precompile function
_precompile_agent()
