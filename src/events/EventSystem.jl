# Event System Module
# Handles event dispatch, communications, state machine, and message handling

module EventSystem

using Aeron
using Clocks
using Hsm
using SnowflakeId
using SpidersFragmentFilters
using SpidersMessageCodecs
using StaticKV
using UnsafeArrays
using ..PropertiesSystem

using ..TimerSystem
using ..MessagingSystem

import Agent.AgentTerminationException

export EventManager, dispatch!, handle_timer_event!,
    setup_communications!, teardown_communications!, is_communications_active,
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
    setup_communications!(em::EventManager)

Set up communication resources for the event manager.
Throws an error if communications are already active.
"""
function setup_communications!(em::EventManager)
    if em.comms !== nothing
        throw(ArgumentError("Communications already active for EventManager"))
    end

    em.comms = CommunicationResources(em)
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

# Communication and message sending functions

# Messaging and serialization interface
@inline function send_event_response(em::EventManager, event, value)
    if em.comms === nothing
        @warn "Cannot send event response: communication resources not initialized"
        return
    end

    # Use shared utility with consistent parameter ordering
    MessagingSystem.send_event_response(
        event,                    # field/event
        value,                    # value - dispatch handles scalar vs array
        em.properties[:Name],     # agent_name
        em.correlation_id,        # correlation_id
        time_nanos(em.clock),     # timestamp_ns
        em.comms.status_stream,   # publication
        em.comms.buf,             # buffer
        em.position_ptr           # position_ptr
    )
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
    status_uri = p[:StatusURI]
    status_stream_id = p[:StatusStreamID]
    status_stream = Aeron.add_publication(em.client, status_uri, status_stream_id)

    control_uri = p[:ControlURI]
    control_stream_id = p[:ControlStreamID]
    control_stream = Aeron.add_subscription(em.client, control_uri, control_stream_id)

    fragment_handler = Aeron.FragmentHandler(control_handler, em)

    if isset(p, :ControlFilter)
        message_filter = SpidersTagFragmentFilter(fragment_handler, p[:ControlFilter])
        control_fragment_handler = Aeron.FragmentAssembler(message_filter)
    else
        control_fragment_handler = Aeron.FragmentAssembler(fragment_handler)
    end

    input_fragment_handler = Aeron.FragmentAssembler(Aeron.FragmentHandler(data_handler, em))
    input_streams = Vector{Aeron.Subscription}(undef, 0)

    # Get the number of sub data connections from properties
    sub_data_connection_count = p[:SubDataConnectionCount]

    # Create subscriptions for each sub data URI/stream pair
    for i in 1:sub_data_connection_count
        uri_prop = Symbol("SubDataURI$(i)")
        stream_prop = Symbol("SubDataStreamID$(i)")

        # Read URI and stream ID from properties
        uri = p[uri_prop]
        stream_id = p[stream_prop]

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

# Convenience accessors
"""
    is_communications_active(em::EventManager)

Check if communications are currently active.
"""
is_communications_active(em::EventManager) = em.comms !== nothing

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
    precompile(Tuple{typeof(setup_communications!),EventManager})
    precompile(Tuple{typeof(teardown_communications!),EventManager})
    precompile(Tuple{typeof(is_communications_active),EventManager})
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
