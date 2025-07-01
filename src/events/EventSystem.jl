# Event System Module
# Handles event dispatch, communications, state machine, and message handling

module EventSystem

using Aeron
using Clocks
using Hsm
using SnowflakeId
using SpidersFragmentFilters
using SpidersMessageCodecs
using UnsafeArrays
using ..PropertiesSystem

using ..TimerSystem

import Agent.AgentTerminationException

export EventManager, dispatch!, handle_timer_event!,
    teardown_communications!,
    send_event_response,
    input_stream_poller, control_poller, poller,
    schedule_timer_event!, schedule_timer_event_at!, cancel_timer!,
    cancel_timer_by_event!, cancel_all_timers!

# Communication resources bundled together
mutable struct CommunicationResources
    # Aeron streams
    status_stream::Aeron.Publication
    control_stream::Aeron.Subscription
    input_streams::Vector{Aeron.Subscription}

    # Named output streams registry
    output_streams::Dict{Symbol,Aeron.Publication}

    # Fragment handlers
    control_fragment_handler::Aeron.FragmentAssembler
    input_fragment_handler::Aeron.FragmentAssembler

    # buffer
    buf::Vector{UInt8}
end

"""
Event management system that encapsulates event dispatch, communications, and state tracking.
"""
@hsmdef mutable struct EventManager{P<:Properties,C<:AbstractClock,I<:SnowflakeIdGenerator}
    client::Aeron.Client
    correlation_id::Int64
    position_ptr::Base.RefValue{Int64}
    comms::Union{Nothing,CommunicationResources}
    properties::P
    clock::C
    id_gen::I
    timer_manager::TimerManager{C}

    function EventManager(client::Aeron.Client, properties::P, clock::C, id_gen::I) where {P,C,I}
        timer_manager = TimerManager(clock)
        new{P,C,I}(client, 0, Ref{Int64}(0), nothing, properties, clock, id_gen, timer_manager)
    end
end

"""
    teardown_communications!(em::EventManager)

Tear down communication resources for the event manager.
"""
function teardown_communications!(em::EventManager)
    if em.comms !== nothing
        # Close streams
        for stream in values(em.comms.output_streams)
            close(stream)
        end
        for stream in em.comms.input_streams
            close(stream)
        end
        close(em.comms.control_stream)
        close(em.comms.status_stream)

        em.comms = nothing
    end
end

"""
    dispatch!(em::EventManager, event::Symbol, message=nothing)

Dispatch an event through the state machine and update state if changed.
"""
function dispatch!(em::EventManager, event::Symbol, message=nothing)
    try
        prev = Hsm.current(em)
        Hsm.dispatch!(em, event, message)
        current = Hsm.current(em)

        if prev != current
            send_event_response(em, :StateChange, current)
        end

    catch e
        if e isa Agent.AgentTerminationException
            @info "Agent termination requested"
            throw(e)
        else
            @error "Error in dispatching event $event" exception = (e, catch_backtrace())
            Hsm.dispatch!(em, :Error, e)
        end
    end
end

"""
    handle_timer_event!(em, em::EventManager, timer_manager, timer_id::Int64, now::Int64)

Handle a timer event by looking up the associated event and dispatching it.
"""
function handle_timer_event!(em::EventManager, timer_id::Int64, now::Int64)
    tm = em.timer_manager
    # Get the event associated with this timer
    event = get(tm.timer_event_map, timer_id, :DefaultTimer)

    # Clean up the mapping
    delete!(tm.timer_event_map, timer_id)

    # Dispatch the timer event
    dispatch!(em, event, now)

    return true
end

# Message handling functions
function control_handler(em::EventManager, buffer, _)
    # A single buffer may contain several Event messages. Decode each one at a time and dispatch
    offset = 0
    while offset < length(buffer)
        message = EventMessageDecoder(buffer, offset; position_ptr=em.position_ptr)
        header = SpidersMessageCodecs.header(message)
        em.correlation_id = SpidersMessageCodecs.correlationId(header)
        event = SpidersMessageCodecs.key(message, Symbol)

        dispatch!(em, event, message)

        offset += sbe_encoded_length(MessageHeader) + sbe_decoded_length(message)
    end
end

function data_handler(em::EventManager, buffer, _)
    message = TensorMessageDecoder(buffer; position_ptr=em.position_ptr)
    header = SpidersMessageCodecs.header(message)
    em.correlation_id = SpidersMessageCodecs.correlationId(header)
    tag = SpidersMessageCodecs.tag(header, Symbol)

    dispatch!(em, tag, message)
    nothing
end

function decode_message(buffer, position_ptr)
    # Decode a single message from the buffer
    message = EventMessageDecoder(buffer; position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(message)
    correlation_id = SpidersMessageCodecs.correlationId(header)
    event = SpidersMessageCodecs.key(message, Symbol)

    return message, correlation_id, event
end

# Communication and message sending functions
function offer(p, buf, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        result = Aeron.offer(p, buf)
        if result > 0
            return
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            continue
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            throw(ErrorException("Publication not connected"))
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
            attempts -= 1
            continue
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            throw(ErrorException("Publication not connected"))
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        end
        attempts -= 1
    end
    throw(ErrorException("Failed to claim buffer after $max_attempts attempts"))
end

# Messaging and serialization interface
@inline function send_event_response(em::EventManager, event, value)
    if em.comms === nothing
        @warn "Cannot send event response: communication resources not initialized"
        return
    end

    agent_name = em.properties[:Name]
    response = EventMessageEncoder(em.comms.buf; position_ptr=em.position_ptr)
    header = SpidersMessageCodecs.header(response)

    SpidersMessageCodecs.timestampNs!(header, time_nanos(em.clock))
    SpidersMessageCodecs.correlationId!(header, em.correlation_id)
    SpidersMessageCodecs.tag!(header, agent_name)
    SpidersMessageCodecs.key!(response, event)
    encode(response, value)

    offer(em.comms.status_stream, convert(AbstractArray{UInt8}, response))
    nothing
end

@inline function send_event_response(em::EventManager, event, value::AbstractArray)
    if em.comms === nothing
        @warn "Cannot send event response: communication resources not initialized"
        return
    end

    agent_name = em.properties[:Name]
    # Encode the buffer in reverse order
    len = sizeof(eltype(value)) * length(value)

    # Use the SBE encoder to create a TensorMessage header
    tensor = TensorMessageEncoder(em.comms.buf; position_ptr=em.position_ptr)
    header = SpidersMessageCodecs.header(tensor)
    SpidersMessageCodecs.timestampNs!(header, time_nanos(em.clock))
    SpidersMessageCodecs.correlationId!(header, em.correlation_id)
    SpidersMessageCodecs.tag!(header, agent_name)
    SpidersMessageCodecs.format!(tensor, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(tensor, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(tensor, Int32.(size(value)))
    SpidersMessageCodecs.origin!(tensor, nothing)
    SpidersMessageCodecs.values_length!(tensor, len)
    # values_length! doesn't increment the position, so we need to do it manually
    SpidersMessageCodecs.sbe_position!(tensor, sbe_position(tensor) + SpidersMessageCodecs.values_header_length(tensor))
    tensor_message = convert(AbstractArray{UInt8}, tensor)
    len += length(tensor_message)

    response = EventMessageEncoder(em.comms.buf, sbe_position(tensor); position_ptr=em.position_ptr)
    header = SpidersMessageCodecs.header(response)
    SpidersMessageCodecs.timestampNs!(header, time_nanos(em.clock))
    SpidersMessageCodecs.correlationId!(header, em.correlation_id)
    SpidersMessageCodecs.tag!(header, agent_name)
    SpidersMessageCodecs.format!(response, SpidersMessageCodecs.Format.SBE)
    SpidersMessageCodecs.key!(response, event)
    SpidersMessageCodecs.value_length!(response, len)
    # value_length! doesn't increment the position, so we need to do it manually
    SpidersMessageCodecs.sbe_position!(response, sbe_position(response) + SpidersMessageCodecs.value_header_length(response))
    response_message = convert(AbstractArray{UInt8}, response)

    # Offer in the correct order
    offer(em.comms.status_stream,
        (
            response_message,
            tensor_message,
            vec(reinterpret(UInt8, value))
        )
    )
    nothing
end

@inline function send_event_response(em::EventManager, event, value::T) where {T<:Union{AbstractString,Real,Symbol,Tuple}}
    if em.comms === nothing
        @warn "Cannot send event response: communication resources not initialized"
        return
    end

    agent_name = em.properties[:Name]
    len = sbe_encoded_length(MessageHeader) +
          sbe_block_length(EventMessage) +
          SpidersMessageCodecs.value_header_length(EventMessage) +
          sizeof(value)

    claim = try_claim(em.comms.status_stream, len)
    response = EventMessageEncoder(buffer(claim); position_ptr=em.position_ptr)
    header = SpidersMessageCodecs.header(response)

    SpidersMessageCodecs.timestampNs!(header, time_nanos(em.clock))
    SpidersMessageCodecs.correlationId!(header, em.correlation_id)
    SpidersMessageCodecs.tag!(header, agent_name)
    SpidersMessageCodecs.key!(response, event)
    encode(response, value)

    Aeron.commit(claim)

    nothing
end

# Timer convenience functions for EventManager
function schedule_timer_event!(em::EventManager, event::Symbol, delay_ns::Int64)
    return TimerSystem.schedule_timer_in!(em.timer_manager, event, delay_ns)
end

function schedule_timer_event_at!(em::EventManager, event::Symbol, deadline_ns::Int64)
    return TimerSystem.schedule_timer_at!(em.timer_manager, deadline_ns, event)
end

function cancel_timer!(em::EventManager, timer_id::Int64)
    return TimerSystem.cancel_timer!(em.timer_manager, timer_id)
end

function cancel_timer_by_event!(em::EventManager, event::Symbol)
    return TimerSystem.cancel_timer_by_event!(em.timer_manager, event)
end

function cancel_all_timers!(em::EventManager)
    return TimerSystem.cancel_all_timers!(em.timer_manager)
end

# Constants
const DEFAULT_FRAGMENT_COUNT_LIMIT = 10

"""
    input_stream_poller(em::EventManager) -> Int

Poll all input streams for incoming data messages.
Returns the number of fragments processed.
"""
function input_stream_poller(em::EventManager)
    work_count = 0

    # Check if communications are set up
    if em.comms === nothing
        return 0
    end

    while true
        all_streams_empty = true
        input_fragment_handler = em.comms.input_fragment_handler

        for subscription in em.comms.input_streams
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

"""
    control_poller(em::EventManager) -> Int

Poll the control stream for incoming control messages.
Returns the number of fragments processed.
"""
function control_poller(em::EventManager)
    # Check if communications are set up
    if em.comms === nothing
        return 0
    end

    return Aeron.poll(em.comms.control_stream, em.comms.control_fragment_handler, DEFAULT_FRAGMENT_COUNT_LIMIT)
end

"""
    poller(em::EventManager) -> Int

Combined poller that polls control streams, input streams, and timers.
Returns the total number of work items processed.
"""
function poller(em::EventManager)
    work_count = 0
    work_count += control_poller(em)
    work_count += input_stream_poller(em)

    # Poll timers - handle timer events through the state machine
    # The TimerSystem.timer_poller expects (handler, timer_manager, context)
    timer_work = TimerSystem.timer_poller(
        (timer_id, now) -> handle_timer_event!(em, timer_id, now),
        em.timer_manager,
        em
    )
    work_count += timer_work

    return work_count
end

"""
    CommunicationResources(em::EventManager)

Create and set up communication resources for the event manager using its client and properties.
"""
function CommunicationResources(em::EventManager)
    p = em.properties
    status_uri = get_property(p, :StatusURI)
    status_stream_id = get_property(p, :StatusStreamID)
    status_stream = Aeron.add_publication(em.client, status_uri, status_stream_id)

    control_uri = get_property(p, :ControlURI)
    control_stream_id = get_property(p, :ControlStreamID)
    control_stream = Aeron.add_subscription(em.client, control_uri, control_stream_id)

    fragment_handler = Aeron.FragmentHandler(control_handler, em)

    if is_set(p, :ControlStreamFilter)
        message_filter = SpidersTagFragmentFilter(fragment_handler, get_property(p, :ControlStreamFilter))
        control_fragment_handler = Aeron.FragmentAssembler(message_filter)
    else
        control_fragment_handler = Aeron.FragmentAssembler(fragment_handler)
    end

    input_fragment_handler = Aeron.FragmentAssembler(Aeron.FragmentHandler(data_handler, em))
    input_streams = Vector{Aeron.Subscription}(undef, 0)

    # Get the number of sub data connections from properties
    sub_data_connection_count = get_property(p, :SubDataConnectionCount)

    # Create subscriptions for each sub data URI/stream pair
    for i in 1:sub_data_connection_count
        uri_prop = Symbol("SubDataURI$(i)")
        stream_prop = Symbol("SubDataStreamID$(i)")

        # Read URI and stream ID from properties
        uri = get_property(p, uri_prop)
        stream_id = get_property(p, stream_prop)

        subscription = Aeron.add_subscription(em.client, uri, stream_id)
        push!(input_streams, subscription)
    end

    CommunicationResources(
        status_stream,
        control_stream,
        input_streams,
        Dict{Symbol,Aeron.Publication}(:Status => status_stream),
        control_fragment_handler,
        input_fragment_handler,
        Vector{UInt8}(undef, 1 << 23)
    )
end

include("utilities.jl")  # Import utility functions
include("states/states.jl")  # Import state machine states

# Precompile statements for EventSystem
function _precompile()
    # EventManager construction - using generic types to avoid module dependencies
    # precompile(Tuple{typeof(EventManager),Any,CachedEpochClock{EpochClock},SnowflakeIdGenerator{CachedEpochClock{EpochClock}},TimerManager{CachedEpochClock{EpochClock}},Aeron.Client})

    # Event dispatch functions
    precompile(Tuple{typeof(dispatch!),Any,EventManager,Symbol,Nothing})
    precompile(Tuple{typeof(dispatch!),Any,EventManager,Symbol,EventMessageDecoder})
    precompile(Tuple{typeof(dispatch!),Any,EventManager,Symbol,TensorMessageDecoder})
    precompile(Tuple{typeof(dispatch!),Any,EventManager,Symbol,Int64})
    precompile(Tuple{typeof(dispatch!),Any,EventManager,Symbol,Any})

    # Timer event handling
    precompile(Tuple{typeof(handle_timer_event!),EventManager,Int64,Int64})

    # Communication setup/teardown
    precompile(Tuple{typeof(teardown_communications!),EventManager})
    precompile(Tuple{typeof(CommunicationResources),EventManager})

    # Polling functions
    precompile(Tuple{typeof(input_stream_poller),EventManager})
    precompile(Tuple{typeof(control_poller),EventManager})
    precompile(Tuple{typeof(poller),EventManager})

    # Message sending functions
    precompile(Tuple{typeof(send_event_response),EventManager,Symbol,String})
    precompile(Tuple{typeof(send_event_response),EventManager,Symbol,Symbol})
    precompile(Tuple{typeof(send_event_response),EventManager,Symbol,Int})
    precompile(Tuple{typeof(send_event_response),EventManager,Symbol,Int64})
    precompile(Tuple{typeof(send_event_response),EventManager,Symbol,Float64})
    precompile(Tuple{typeof(send_event_response),EventManager,Symbol,Bool})
    precompile(Tuple{typeof(send_event_response),EventManager,Symbol,Any})

    # Timer convenience functions
    precompile(Tuple{typeof(schedule_timer_event!),EventManager,Symbol,Int64})
    precompile(Tuple{typeof(schedule_timer_event_at!),EventManager,Symbol,Int64})
    precompile(Tuple{typeof(cancel_timer!),EventManager,Int64})
    precompile(Tuple{typeof(cancel_timer_by_event!),EventManager,Symbol})
    precompile(Tuple{typeof(cancel_all_timers!),EventManager})
end

# Call precompile function
_precompile()

end # module EventSystem
