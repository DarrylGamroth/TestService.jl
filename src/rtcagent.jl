using Hsm
using LightSumTypes
using SnowflakeId
using SpidersFragmentFilters
using SpidersMessageCodecs
using UnsafeArrays

include("Timers/Timers.jl")
using .Timers

include("exceptions.jl")
include("communications.jl")
include("strategies.jl")

export RtcAgent, dispatch!,
    send_event_response,
    input_poller, control_poller, property_poller, timer_poller,
    PublishStrategy, OnUpdate, Periodic, Scheduled, RateLimited,
    register!, unregister!, isregistered, list, get_publication,
    PolledTimer,
    should_publish, next_time,
    # Exception types
    AgentError, AgentStateError, AgentStartupError, ClaimBufferError,
    CommunicationError, CommunicationNotInitializedError, StreamNotFoundError,
    PublicationBackPressureError, SubscriptionError, MessageProcessingError

const DEFAULT_FRAGMENT_COUNT_LIMIT = 10
const DEFAULT_PUBLICATION_BUFFER_SIZE = (1 << 21)

mutable struct PublicationConfig
    field::Symbol
    stream::Aeron.Publication
    stream_index::Int
    strategy::PublishStrategy
    last_published_ns::Int64
    next_scheduled_ns::Int64
end

struct CommunicationResources
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

    function CommunicationResources(client::Aeron.Client, p::Properties, clientd)
        status_uri = p[:StatusURI]
        status_stream_id = p[:StatusStreamID]
        status_stream = Aeron.add_publication(client, status_uri, status_stream_id)

        control_uri = p[:ControlURI]
        control_stream_id = p[:ControlStreamID]
        control_stream = Aeron.add_subscription(client, control_uri, control_stream_id)

        fragment_handler = Aeron.FragmentHandler(control_handler, clientd)

        if isset(p, :ControlFilter)
            message_filter = SpidersTagFragmentFilter(fragment_handler, p[:ControlFilter])
            control_fragment_handler = Aeron.FragmentAssembler(message_filter)
        else
            control_fragment_handler = Aeron.FragmentAssembler(fragment_handler)
        end

        input_fragment_handler = Aeron.FragmentAssembler(Aeron.FragmentHandler(data_handler, clientd))
        input_streams = Aeron.Subscription[]

        # Get the number of sub data connections from properties
        sub_data_connection_count = p[:SubDataConnectionCount]

        # Create subscriptions for each sub data URI/stream pair
        for i in 1:sub_data_connection_count
            uri_key = Symbol("SubDataURI$i")
            stream_id_key = Symbol("SubDataStreamID$i")

            if haskey(p, uri_key) && haskey(p, stream_id_key)
                uri = p[uri_key]
                stream_id = p[stream_id_key]
                subscription = Aeron.add_subscription(client, uri, stream_id)
                push!(input_streams, subscription)
            end
        end

        # Initialize output streams registry and buffer
        output_streams = Dict{Symbol,Aeron.Publication}()

        # Set up PubData publications
        if haskey(p, :PubDataConnectionCount)
            pub_data_connection_count = p[:PubDataConnectionCount]

            for i in 1:pub_data_connection_count
                uri_key = Symbol("PubDataURI$i")
                stream_id_key = Symbol("PubDataStreamID$i")

                if haskey(p, uri_key) && haskey(p, stream_id_key)
                    uri = p[uri_key]
                    stream_id = p[stream_id_key]
                    publication = Aeron.add_publication(client, uri, stream_id)
                    output_streams[Symbol("PubData$i")] = publication
                    @info "Created publication $i: $uri (stream ID: $stream_id)"
                else
                    @warn "Missing URI or stream ID for pub data connection $i"
                end
            end
        else
            @info "No PubDataConnectionCount found in properties, no publications created"
        end

        buf = Vector{UInt8}(undef, 1 << 23)  # Default buffer size

        new(
            status_stream,
            control_stream,
            input_streams,
            output_streams,
            control_fragment_handler,
            input_fragment_handler,
            buf
        )
    end
end

"""
Event management system that encapsulates event dispatch, communications, and state tracking.
"""
@hsmdef mutable struct RtcAgent{C<:AbstractClock,P<:AbstractStaticKV,ID<:SnowflakeIdGenerator,ET<:PolledTimer}
    client::Aeron.Client
    correlation_id::Int64
    position_ptr::Base.RefValue{Int64}
    comms::Union{Nothing,CommunicationResources}
    clock::C
    properties::P
    id_gen::ID
    timers::ET
    property_registry::Vector{PublicationConfig}
end

function RtcAgent(client::Aeron.Client, properties::Properties, clock::C=CachedEpochClock(EpochClock())) where {C<:Clocks.AbstractClock}
    fetch!(clock)

    id_gen = SnowflakeIdGenerator(properties[:NodeId], clock)
    timers = PolledTimer(clock)

    # Create the agent with property management fields
    RtcAgent(
        client,
        0,
        Ref{Int64}(0),
        nothing,
        clock,
        properties,
        id_gen,
        timers,
        PublicationConfig[]
    )
end

"""
    Base.open(agent::RtcAgent)

Set up communication resources for the event manager.
Throws an error if communications are already active.
"""
function Base.open(agent::RtcAgent)
    if isopen(agent)
        throw(AgentStateError(:Open, "open communications"))
    end

    try
        agent.comms = CommunicationResources(agent.client, agent.properties, agent)
    catch e
        throw(AgentCommunicationError("Failed to initialize communication resources: $(e)"))
    end
end

"""
    Base.isopen(agent::RtcAgent) -> Bool

Check if communications are open for the agent.
"""
Base.isopen(agent::RtcAgent) = !isnothing(agent.comms)

"""
    Base.close(agent::RtcAgent)

Tear down communication resources for the event manager.
"""
function Base.close(agent::RtcAgent)
    if isopen(agent)
        # Close streams
        for stream in values(agent.comms.output_streams)
            close(stream)
        end
        for stream in agent.comms.input_streams
            close(stream)
        end
        close(agent.comms.control_stream)
        close(agent.comms.status_stream)

        agent.comms = nothing
    end
end

"""
    dispatch!(agent::RtcAgent, event::Symbol, message=nothing)

Dispatch an event through the state machine and update state if changed.
"""
function dispatch!(agent::RtcAgent, event::Symbol, message=nothing)
    try
        prev = Hsm.current(agent)
        Hsm.dispatch!(agent, event, message)
        current = Hsm.current(agent)

        if prev != current
            send_event_response(agent, :StateChange, current)
        end

    catch e
        if e isa Agent.AgentTerminationException
            @info "Agent termination requested"
            throw(e)
        else
            @error "Error in dispatching event $event" exception = (e, catch_backtrace())
            Hsm.dispatch!(agent, :Error, e)
        end
    end
end

# Message handling functions
function control_handler(agent::RtcAgent, buffer, _)
    # A single buffer may contain several Event messages. Decode each one at a time and dispatch
    offset = 0
    while offset < length(buffer)
        message = EventMessageDecoder(buffer, offset; position_ptr=agent.position_ptr)
        header = SpidersMessageCodecs.header(message)
        agent.correlation_id = SpidersMessageCodecs.correlationId(header)
        event = SpidersMessageCodecs.key(message, Symbol)

        dispatch!(agent, event, message)

        offset += sbe_encoded_length(MessageHeader) + sbe_decoded_length(message)
    end
    nothing
end

function data_handler(agent::RtcAgent, buffer, _)
    message = TensorMessageDecoder(buffer; position_ptr=agent.position_ptr)
    header = SpidersMessageCodecs.header(message)
    agent.correlation_id = SpidersMessageCodecs.correlationId(header)
    tag = SpidersMessageCodecs.tag(header, Symbol)

    dispatch!(agent, tag, message)
    nothing
end

"""
    input_poller(agent::RtcAgent) -> Int

Poll all input streams for incoming data messages.
Returns the number of fragments processed.
"""
function input_poller(agent::RtcAgent)
    work_count = 0

    while true
        all_streams_empty = true
        input_fragment_handler = agent.comms.input_fragment_handler

        for subscription in agent.comms.input_streams
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
    control_poller(agent::RtcAgent) -> Int

Poll the control stream for incoming control messages.
Returns the number of fragments processed.
"""
function control_poller(agent::RtcAgent)
    return Aeron.poll(agent.comms.control_stream, agent.comms.control_fragment_handler, DEFAULT_FRAGMENT_COUNT_LIMIT)
end

function timer_poller(agent::RtcAgent)
    Timers.poll(agent.timers, agent) do event, now, agent
        dispatch!(agent, event, now)
    end
end

function property_poller(agent::RtcAgent)
    if isempty(agent.property_registry)
        return 0
    end

    published_count = 0

    # Process each registered publication
    for config in agent.property_registry
        published_count += publish_property!(agent, config)
    end

    return published_count
end

"""
    get_publication(agent::RtcAgent, stream_index::Int) -> Aeron.Publication

Get a publication stream by index (1-based).
"""
function get_publication(agent::RtcAgent, stream_index::Int)
    if !isopen(agent)
        throw(CommunicationNotInitializedError("get publication stream"))
    end

    output_streams = agent.comms.output_streams
    pub_key = Symbol("PubData$stream_index")

    if !haskey(output_streams, pub_key)
        throw(StreamNotFoundError("PubData$stream_index", stream_index))
    end

    return output_streams[pub_key]
end

"""
    register!(agent::RtcAgent, field::Symbol, stream_index::Int, strategy::PublishStrategy)

Register a property for publication using a publication stream by index.
The stream_index corresponds to the publication stream (1-based).
A property can be registered multiple times with different streams and strategies.
"""
function register!(agent::RtcAgent,
    field::Symbol,
    stream_index::Int,
    strategy::PublishStrategy)

    # Get the publication stream (this will validate bounds and availability)
    publication = get_publication(agent, stream_index)

    # Create and add the configuration to the registry
    config = PublicationConfig(
        field,
        publication,
        stream_index,
        strategy,
        -1,        # Never published
        next_time(strategy, 0)
    )
    push!(agent.property_registry, config)

    @info "Registered property: $field on stream $stream_index with strategy $strategy"
end

"""
    unregister!(agent::RtcAgent, field::Symbol, stream_index::Int) -> Int

Remove a specific property-stream registration from the publication registry.
Returns the number of registrations removed (0 or 1).
"""
function unregister!(agent::RtcAgent, field::Symbol, stream_index::Int)
    if !isregistered(agent, field, stream_index)
        return 0
    end

    indices = findall(config -> config.field == field && config.stream_index == stream_index, agent.property_registry)
    deleteat!(agent.property_registry, indices)

    @info "Unregistered property: $field on stream $stream_index"

    return length(indices)
end

"""
    unregister!(agent::RtcAgent, field::Symbol) -> Int

Remove all registrations for a property field from the publication registry.
Returns the number of registrations removed.
"""
function unregister!(agent::RtcAgent, field::Symbol)
    if !isregistered(agent, field)
        return 0
    end

    indices = findall(config -> config.field == field, agent.property_registry)
    deleteat!(agent.property_registry, indices)

    @info "Unregistered property: $field"

    return length(indices)
end

"""
    isregistered(agent::RtcAgent, field::Symbol) -> Bool
    isregistered(agent::RtcAgent, field::Symbol, stream_index::Int) -> Bool

Check if a property is registered for publication.
With only field specified, returns true if the field is registered on any stream.
With both field and stream_index specified, returns true if the field is registered on that specific stream.
"""
isregistered(agent::RtcAgent, field::Symbol) = any(config -> config.field == field, agent.property_registry)
isregistered(agent::RtcAgent, field::Symbol, stream_index::Int) = any(config -> config.field == field && config.stream_index == stream_index, agent.property_registry)

"""
    list(agent::RtcAgent)

Return a list of all currently registered property publications as (field, stream_index, strategy) tuples.
"""
function list(agent::RtcAgent)
    return [(config.field, config.stream_index, config.strategy) for config in agent.property_registry]
end

"""
    empty!(agent::RtcAgent) -> Int

Clear all registered publications. Returns the number of registrations removed.
"""
function Base.empty!(agent::RtcAgent)
    count = length(agent.property_registry)
    empty!(agent.property_registry)
    return count
end

"""
    publish_property!(agent::RtcAgent, config::PublicationConfig)

Process a single property publication based on its strategy and timing.
Returns 1 if processed (regardless of whether published), 0 if skipped.
"""
@inline function publish_property!(agent::RtcAgent, config::PublicationConfig)
    # Get current time for this publication cycle
    now = time_nanos(agent.clock)

    # Early exit if strategy says not to publish based on timing
    property_timestamp_ns = last_update(agent.properties, config.field)
    if !should_publish(config.strategy,
        config.last_published_ns,
        config.next_scheduled_ns,
        property_timestamp_ns,
        now)
        return 0
    end

    publish_value(
        config.field,
        agent.properties[config.field],
        agent.properties[:Name],
        next_id(agent.id_gen),
        now,
        config.stream,
        agent.comms.buf,
        agent.position_ptr
    )
    config.last_published_ns = now
    config.next_scheduled_ns = next_time(config.strategy, now)

    return 1
end

# =============================================================================
# Agent Interface Implementation
# =============================================================================

"""
Get the name of this agent.
"""
Agent.name(agent::RtcAgent) = agent.properties[:Name]

"""
Initialize the agent by setting up communications and starting the state machine.
"""
function Agent.on_start(agent::RtcAgent)
    @info "Starting agent $(Agent.name(agent))"

    # Setup communications
    open(agent)

    return nothing
end

"""
Shutdown the agent by tearing down communications and stopping timers.
"""
function Agent.on_close(agent::RtcAgent)
    @info "Stopping agent $(Agent.name(agent))"

    # Cancel all timers
    cancel!(agent.timers)

    # Teardown communications
    close(agent)

    return nothing
end

function Agent.on_error(agent::RtcAgent, error)
    @error "Error in agent $(Agent.name(agent)):" exception = (error, catch_backtrace())
end

"""
Perform one unit of work by polling communications, timers, and processing events.
"""
function Agent.do_work(agent::RtcAgent)
    fetch!(agent.clock)

    work_count = 0
    work_count += input_poller(agent)
    work_count += property_poller(agent)
    work_count += timer_poller(agent)
    work_count += control_poller(agent)

    return work_count
end

include("utilities.jl")
include("states/states.jl")
include("precompile.jl")
