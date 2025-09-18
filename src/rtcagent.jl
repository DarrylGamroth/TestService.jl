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

export RtcAgent,
    # Publishing strategies for extension services
    PublishStrategy, OnUpdate, Periodic, Scheduled, RateLimited,
    # Property registration for extension services
    register!, unregister!, isregistered, list,
    # Timer scheduling for extension services
    PolledTimer, schedule!, schedule_at!, cancel!

const DEFAULT_INPUT_FRAGMENT_COUNT_LIMIT = 10
const DEFAULT_CONTROL_FRAGMENT_COUNT_LIMIT = 1

"""
    PublicationConfig

Configuration for property publication with timing and strategy management.

Tracks publication state and controls when property values are published based
on the configured strategy. Fields are ordered by access frequency.

# Fields
- `last_published_ns::Int64`: timestamp of last publication in nanoseconds
- `next_scheduled_ns::Int64`: next scheduled publication time in nanoseconds
- `field::Symbol`: property field name to publish
- `stream_index::Int`: target output stream index (1-based)
- `strategy::PublishStrategy`: publication timing strategy
- `stream::Aeron.ExclusivePublication`: direct stream reference for efficiency
"""
mutable struct PublicationConfig
    last_published_ns::Int64
    next_scheduled_ns::Int64
    field::Symbol
    stream_index::Int
    strategy::PublishStrategy
    stream::Aeron.ExclusivePublication
end

# Include proxy modules before RtcAgent struct to make types available
include("status_proxy.jl")
include("property_proxy.jl")

"""
    RtcAgent{C,P,ID,ET}

Real-time control agent with hierarchical state machine and communication.

Manages event dispatch, property publishing, timer scheduling, and state
transitions. Generic parameters allow customization of core components.

# Type Parameters
- `C<:AbstractClock`: clock implementation for timing operations
- `P<:AbstractStaticKV`: property store implementation
- `ID<:SnowflakeIdGenerator`: unique ID generator for correlation
- `ET<:PolledTimer`: timer implementation for scheduled operations

# Fields
- `clock::C`: timing source for all operations
- `properties::P`: agent configuration and runtime properties
- `id_gen::ID`: correlation ID generator
- `source_correlation_id::Int64`: correlation ID of current event being processed
- `timers::ET`: timer scheduler for periodic operations
- `comms::CommunicationResources`: Aeron stream management
- `status_proxy::Union{Nothing,StatusProxy}`: status publishing interface
- `property_proxy::Union{Nothing,PropertyProxy}`: property publishing interface
- `control_adapter::Union{Nothing,ControlStreamAdapter}`: control message handler
- `input_adapters::Vector{InputStreamAdapter}`: input stream processors
- `property_registry::Vector{PublicationConfig}`: registered property configs
"""
@hsmdef mutable struct RtcAgent{C<:AbstractClock,P<:AbstractStaticKV,ID<:SnowflakeIdGenerator,ET<:PolledTimer}
    clock::C
    properties::P
    id_gen::ID
    source_correlation_id::Int64
    timers::ET
    comms::CommunicationResources
    status_proxy::Union{Nothing,StatusProxy}
    property_proxy::Union{Nothing,PropertyProxy}
    control_adapter::Union{Nothing,ControlStreamAdapter}
    input_adapters::Vector{InputStreamAdapter}
    property_registry::Vector{PublicationConfig}
end

function RtcAgent(comms::CommunicationResources, properties::AbstractStaticKV, clock::C=CachedEpochClock(EpochClock())) where {C<:Clocks.AbstractClock}
    fetch!(clock)

    id_gen = SnowflakeIdGenerator(properties[:NodeId], clock)
    timers = PolledTimer(clock)

    # Create the agent with proxy fields initialized to nothing
    RtcAgent(
        clock,
        properties,
        id_gen,
        0,
        timers,
        comms,
        nothing,
        nothing,
        nothing,
        InputStreamAdapter[],
        PublicationConfig[]
    )
end

# =============================================================================
# Agent Convenience Functions for Proxy Operations
# =============================================================================

"""
    publish_status_event(agent, event, data)

Publish a status event using the agent's status proxy.

Convenience method that automatically handles timestamp generation and agent name.
Throws `AgentStateError` if the status proxy is not initialized.
"""
function publish_status_event(agent::RtcAgent, event::Symbol, data)
    timestamp = time_nanos(agent.clock)
    proxy = agent.status_proxy::StatusProxy

    return publish_status_event(
        proxy, event, data, agent.properties[:Name], agent.source_correlation_id, timestamp
    )
end

"""
    publish_state_change(agent, new_state)

Publish a state change event using the agent's status proxy.

Convenience method for reporting agent state transitions.
"""
function publish_state_change(agent::RtcAgent, new_state::Symbol)
    timestamp = time_nanos(agent.clock)
    proxy = agent.status_proxy::StatusProxy

    return publish_state_change(
        proxy, new_state, agent.properties[:Name], agent.source_correlation_id, timestamp
    )
end

"""
Publish an event response using the agent's status proxy (convenience method).
"""
function publish_event_response(agent::RtcAgent, event::Symbol, value)
    timestamp = time_nanos(agent.clock)
    proxy = agent.status_proxy::StatusProxy

    return publish_event_response(
        proxy, event, value, agent.properties[:Name], agent.source_correlation_id, timestamp
    )
end

"""
Publish a property value to a specific output stream using the agent's property proxy (convenience method).
"""
function publish_property(agent::RtcAgent, stream_index::Int, field::Symbol, value)
    # Validate field exists in properties
    if !haskey(agent.properties, field)
        throw(KeyError("Property $field not found in agent"))
    end

    timestamp = time_nanos(agent.clock)
    proxy = agent.property_proxy::PropertyProxy

    return publish_property(proxy, stream_index, field, value,
        agent.properties[:Name], agent.source_correlation_id, timestamp)
end

"""
Publish a single property update with strategy evaluation using the agent's property proxy (convenience method).
"""
function publish_property_update(agent::RtcAgent, config::PublicationConfig)
    timestamp = time_nanos(agent.clock)
    correlation_id = next_id(agent.id_gen)
    proxy = agent.property_proxy::PropertyProxy

    # Delegate to proxy with business logic parameters
    return publish_property_update(proxy, config, agent.properties,
        agent.properties[:Name], correlation_id, timestamp)
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
            publish_state_change(agent, current)
        end

    catch e
        if e isa Agent.AgentTerminationException
            @info "Agent termination requested"
            throw(e)
        else
            Hsm.dispatch!(agent, :Error, (event, e::Exception))
        end
    end
end

"""
    input_poller(agent::RtcAgent) -> Int

Poll all input streams for incoming data messages using input stream adapters.
Returns the number of fragments processed.
"""
function input_poller(agent::RtcAgent)
    poll(agent.input_adapters, DEFAULT_INPUT_FRAGMENT_COUNT_LIMIT)
end

"""
    control_poller(agent::RtcAgent) -> Int

Poll the control stream for incoming control messages using the control stream adapter.
Returns the number of fragments processed.
"""
function control_poller(agent::RtcAgent)
    adapter = agent.control_adapter::ControlStreamAdapter
    poll(adapter, DEFAULT_CONTROL_FRAGMENT_COUNT_LIMIT)
end

function timer_poller(agent::RtcAgent)
    Timers.poll(agent.timers, agent) do event, now, agent
        agent.source_correlation_id = next_id(agent.id_gen)
        dispatch!(agent, event, now)
    end
end

"""
    should_poll_properties(agent::RtcAgent) -> Bool

Determine whether property polling should be active based on agent state.
"""
function should_poll_properties(agent::RtcAgent)
    return Hsm.current(agent) === :Playing
end

"""
    property_poller(agent::RtcAgent) -> Int

    Poll all registered properties for updates.
"""
function property_poller(agent::RtcAgent)
    if !should_poll_properties(agent) || isempty(agent.property_registry)
        return 0
    end

    published_count = 0
    registry = agent.property_registry

    @inbounds for i in 1:length(registry)
        published_count += publish_property_update(agent, registry[i])
    end

    return published_count
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

    # Validate stream index and get publication
    output_streams = agent.comms.output_streams
    if stream_index < 1 || stream_index > length(output_streams)
        throw(StreamNotFoundError("PubData$stream_index", stream_index))
    end

    # Create and add the configuration to the registry
    config = PublicationConfig(
        -1,
        next_time(strategy, 0),
        field,
        stream_index,
        strategy,
        output_streams[stream_index]
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
    empty!(agent::RtcAgent) -> Int

Clear all registered publications. Returns the number of registrations removed.
"""
function Base.empty!(agent::RtcAgent)
    count = length(agent.property_registry)
    empty!(agent.property_registry)
    return count
end

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
            agent
        )

        # Create input stream adapters
        empty!(agent.input_adapters)
        for input_stream in agent.comms.input_streams
            push!(agent.input_adapters, InputStreamAdapter(input_stream, agent))
        end

        # Create proxy instances
        agent.status_proxy = StatusProxy(agent.comms.status_stream)
        agent.property_proxy = PropertyProxy(agent.comms.output_streams)

    catch e
        throw(AgentCommunicationError("Failed to initialize communication resources: $(e)"))
    end

    nothing
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

    # Clear adapters and proxies
    agent.control_adapter = nothing
    agent.status_proxy = nothing
    agent.property_proxy = nothing
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

include("property_handlers.jl")
include("states/states.jl")
include("precompile.jl")
