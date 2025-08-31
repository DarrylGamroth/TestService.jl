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
    input_poller, control_poller, property_poller, timer_poller,
    PublishStrategy, OnUpdate, Periodic, Scheduled, RateLimited,
    publish_status_event, publish_state_change,
    publish_property, publish_property_update,
    StatusProxy, PropertyProxy,  # Export proxy struct types
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

# Include proxy modules before RtcAgent struct to make types available
include("status_proxy.jl")
include("property_proxy.jl")

@hsmdef mutable struct RtcAgent{C<:AbstractClock,P<:AbstractStaticKV,ID<:SnowflakeIdGenerator,ET<:PolledTimer}
    client::Aeron.Client
    source_correlation_id::Int64
    comms::CommunicationResources
    control_adapter::Union{Nothing,ControlStreamAdapter}
    input_adapters::Vector{InputStreamAdapter}
    status_proxy::Union{Nothing,StatusProxy}
    property_proxy::Union{Nothing,PropertyProxy}
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

    # Create the agent with proxy fields initialized to nothing
    RtcAgent(
        client,
        0,
        comms,
        nothing,                    # control_adapter
        InputStreamAdapter[],       # input_adapters
        nothing,                    # status_proxy
        nothing,                    # property_proxy
        clock,
        properties,
        id_gen,
        timers,
        PublicationConfig[]
    )
end

# =============================================================================
# Agent Convenience Functions for Proxy Operations
# =============================================================================

"""
Publish a status event using the agent's status proxy (convenience method).
"""
function publish_status_event(agent::RtcAgent, event::Symbol, data=nothing)
    if isnothing(agent.status_proxy)
        throw(AgentStateError(event, "Agent status proxy not initialized"))
    end

    correlation_id = next_id(agent.id_gen)
    timestamp = time_nanos(agent.clock)

    return publish_status_event(
        agent.status_proxy, event, data, agent.properties[:Name], correlation_id, timestamp
    )
end

"""
Publish a status event using the agent's status proxy with specific correlation ID (convenience method).
"""
function publish_status_event(agent::RtcAgent, event::Symbol, data, correlation_id::Int64)
    if isnothing(agent.status_proxy)
        throw(AgentStateError(event, "Agent status proxy not initialized"))
    end

    timestamp = time_nanos(agent.clock)

    return publish_status_event(
        agent.status_proxy, event, data, agent.properties[:Name], correlation_id, timestamp
    )
end

"""
Publish a state change event using the agent's status proxy (convenience method).
"""
function publish_state_change(agent::RtcAgent, new_state::Symbol)
    if isnothing(agent.status_proxy)
        throw(AgentStateError(new_state, "Agent status proxy not initialized"))
    end

    correlation_id = next_id(agent.id_gen)
    timestamp = time_nanos(agent.clock)

    return publish_state_change(
        agent.status_proxy, new_state, agent.properties[:Name], correlation_id, timestamp
    )
end

"""
Publish an event response using the agent's status proxy (convenience method).
"""
function publish_event_response(agent::RtcAgent, event::Symbol, value)
    if isnothing(agent.status_proxy)
        throw(AgentStateError(event, "Agent status proxy not initialized"))
    end

    correlation_id = next_id(agent.id_gen)
    timestamp = time_nanos(agent.clock)

    return publish_event_response(
        agent.status_proxy, event, value, agent.properties[:Name], correlation_id, timestamp
    )
end

"""
Publish a property value to a specific output stream using the agent's property proxy (convenience method).
"""
function publish_property(agent::RtcAgent, stream_index::Int, field::Symbol, value)
    if isnothing(agent.property_proxy)
        throw(AgentStateError(field, "Agent property proxy not initialized"))
    end

    # Validate field exists in properties
    if !haskey(agent.properties, field)
        throw(KeyError("Property $field not found in agent"))
    end

    correlation_id = next_id(agent.id_gen)
    timestamp = time_nanos(agent.clock)

    return publish_property(
        agent.property_proxy, stream_index, field, value,
        agent.properties[:Name], correlation_id, timestamp
    )
end

"""
Publish a single property update with strategy evaluation using the agent's property proxy (convenience method).
"""
function publish_property_update(agent::RtcAgent, config::PublicationConfig)
    if isnothing(agent.property_proxy)
        throw(AgentStateError(config.field, "Agent property proxy not initialized"))
    end

    now = time_nanos(agent.clock)

    # Delegate to proxy with business logic parameters
    return publish_property_update(
        agent.property_proxy, config, agent.properties,
        agent.properties[:Name], agent.id_gen, now
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
            publish_state_change(agent, current)
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
        agent.source_correlation_id = next_id(agent.id_gen)
        dispatch!(agent, event, now)
    end
end

"""
    should_poll_properties(agent::RtcAgent) -> Bool

Determine whether property polling should be active based on agent state.
"""
@inline function should_poll_properties(agent::RtcAgent)
    return Hsm.current(agent) === :Playing
end

function property_poller(agent::RtcAgent)
    if !should_poll_properties(agent) || isempty(agent.property_registry)
        return 0
    end

    published_count = 0

    # Process each registered publication
    for config in agent.property_registry
        published_count += publish_property_update(agent, config)
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

        # Create proxy instances
        agent.status_proxy = StatusProxy(
            Ref{Int64}(0),
            Vector{UInt8}(undef, 1 << 20),
            agent.comms.status_stream
        )

        agent.property_proxy = PropertyProxy(
            Ref{Int64}(0),
            Vector{UInt8}(undef, 1 << 20),
            agent.comms.output_streams
        )

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
    empty!(agent.input_adapters)
    agent.status_proxy = nothing
    agent.property_proxy = nothing
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
