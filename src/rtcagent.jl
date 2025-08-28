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
include("communication_resources.jl")
include("control_stream_adapter.jl")
include("input_stream_adapter.jl")

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

"""
Event management system that encapsulates event dispatch, communications, and state tracking.
"""
@hsmdef mutable struct RtcAgent{C<:AbstractClock,P<:AbstractStaticKV,ID<:SnowflakeIdGenerator,ET<:PolledTimer}
    client::Aeron.Client
    correlation_id::Int64
    position_ptr::Base.RefValue{Int64}
    comms::CommunicationResources
    control_adapter::Union{Nothing,ControlStreamAdapter}
    input_adapters::Vector{InputStreamAdapter}
    clock::C
    properties::P
    id_gen::ID
    timers::ET
    property_registry::Vector{PublicationConfig}
end

function RtcAgent(client::Aeron.Client, comms::CommunicationResources, properties::Properties, clock::C=CachedEpochClock(EpochClock())) where {C<:Clocks.AbstractClock}
    fetch!(clock)

    id_gen = SnowflakeIdGenerator(properties[:NodeId], clock)
    timers = PolledTimer(clock)

    # Create the agent with property management fields
    RtcAgent(
        client,
        0,
        Ref{Int64}(0),
        comms,
        nothing,
        InputStreamAdapter[],
        clock,
        properties,
        id_gen,
        timers,
        PublicationConfig[]
    )
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

"""
    input_poller(agent::RtcAgent) -> Int

Poll all input streams for incoming data messages using input stream adapters.
Returns the number of fragments processed.
"""
function input_poller(agent::RtcAgent)
    poll(agent.input_adapters, DEFAULT_FRAGMENT_COUNT_LIMIT)
end

"""
    control_poller(agent::RtcAgent) -> Int

Poll the control stream for incoming control messages using the control stream adapter.
Returns the number of fragments processed.
"""
function control_poller(agent::RtcAgent)
    poll(agent.control_adapter, DEFAULT_FRAGMENT_COUNT_LIMIT)
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
    output_streams = agent.comms.output_streams

    if stream_index < 1 || stream_index > length(output_streams)
        throw(StreamNotFoundError("PubData$stream_index", stream_index))
    end

    return output_streams[stream_index]
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

    try
        # Create control stream adapter
        agent.control_adapter = ControlStreamAdapter(
            agent.comms.control_stream,
            agent.properties,
            agent
        )

        # Create input stream adapters
        empty!(agent.input_adapters)
        for input_stream in agent.comms.input_streams
            push!(agent.input_adapters, InputStreamAdapter(input_stream, agent))
        end

    catch e
        throw(AgentCommunicationError("Failed to initialize communication resources: $(e)"))
    end
end

"""
Shutdown the agent by tearing down communications and stopping timers.
"""
function Agent.on_close(agent::RtcAgent)
    @info "Stopping agent $(Agent.name(agent))"

    # Cancel all timers
    cancel!(agent.timers)

    # Close communication resources
    close(agent.comms)
    
    # Clear adapters
    agent.control_adapter = nothing
    empty!(agent.input_adapters)
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
