# RTC Agent Module
# Main agent coordination system using the new modular architecture

using Aeron
using Agent
using Clocks
using SnowflakeId
using UnsafeArrays

# Import property system
include("properties/PropertiesSystem.jl")
include("timer/TimerSystem.jl")
include("events/EventSystem.jl")

using .PropertiesSystem
using .EventSystem
using .EventSystem: CommunicationResources

# Main RTC agent/state machine
struct RtcAgent{C<:Clocks.AbstractClock}
    client::Aeron.Client
    properties::Properties{C}
    clock::C
    id_gen::SnowflakeIdGenerator{C}
    event_manager::EventManager{Properties{C},C,SnowflakeIdGenerator{C}}
    properties_manager::PropertiesManager{Properties{C},C,SnowflakeIdGenerator{C}}
end

function RtcAgent(client::Aeron.Client, clock::C=CachedEpochClock(EpochClock())) where {C<:Clocks.AbstractClock}
    fetch!(clock)  # Initialize the clock

    # Initialize properties with the current clock
    properties = Properties(clock)

    id_gen = SnowflakeIdGenerator(properties[:NodeId], clock)

    # Initialize the event system (timer system is now internal to EventSystem)
    event_manager = EventManager(client, properties, clock, id_gen)

    # Initialize the properties manager
    properties_manager = PropertiesManager(client, properties, clock, id_gen)

    RtcAgent{C}(
        client,
        properties,
        clock,
        id_gen,
        event_manager,
        properties_manager
    )
end

Agent.name(agent::RtcAgent) = agent.properties[:Name]

function Agent.on_start(agent::RtcAgent)
    @info "Starting agent $(Agent.name(agent))"
end

function Agent.on_close(agent::RtcAgent)
    @info "Closing agent $(Agent.name(agent))"

    # Teardown event system communications
    EventSystem.teardown_communications!(agent.event_manager)
end

function Agent.on_error(agent::RtcAgent, error)
    @error "Error in agent $(Agent.name(agent)): $error" exception = (error, catch_backtrace())
    exit(1)  # Exit on error
end

function Agent.do_work(agent::RtcAgent)
    # Update the cached clock
    fetch!(agent.clock)

    work_count = 0

    # EventSystem poller now handles input, control, and timer polling
    work_count += EventSystem.poller(agent.event_manager)
    work_count += PropertiesSystem.poller(agent.properties_manager)

    return work_count
end

# Communication setup function
function setup_communications!(agent::RtcAgent, comms::CommunicationResources)
    EventSystem.setup_communications!(agent.event_manager, comms)

    # Set up fragment handlers to use the event system directly
    agent.event_manager.comms.control_fragment_handler = Aeron.FragmentAssembler((buffer, header) -> EventSystem.control_handler(agent, agent.event_manager, buffer, header))
    agent.event_manager.comms.input_fragment_handler = Aeron.FragmentAssembler((buffer, header) -> EventSystem.data_handler(agent, agent.event_manager, buffer, header))
end

# Example function to demonstrate property publication setup
"""
    setup_example_publications(agent::RtcAgent)

Set up some example property publications for demonstration.
This function shows how to register properties for publication with different strategies.
"""
# function setup_example_publications(agent::RtcAgent)
#     if agent.event_manager.comms === nothing
#         @warn "Cannot setup publications: communication resources not initialized"
#         return
#     end

#     # Use the status stream for these examples
#     status_stream = agent.event_manager.comms.status_stream

#     # Register some properties with different strategies
#     try
#         # Publish connection count changes immediately when they are updated
#         register_on_update_publication(:ConnectionCount, status_stream)

#         # Publish heartbeat period every 5 seconds
#         register_periodic_publication(:HeartbeatPeriodNs, status_stream, 5000)

#         # Publish node ID on change, but rate-limited to once per second
#         register_rate_limited_publication(:NodeId, status_stream, 1000)

#         @info "Example property publications registered" count = length(list())
#     catch e
#         @error "Error setting up example publications" exception = (e, catch_backtrace())
#     end
# end

# Precompile statements for RtcAgent
function _precompile()
    # Core types - use concrete clock type for precompilation
    ClockType = CachedEpochClock{EpochClock}
    AgentType = RtcAgent{ClockType}

    precompile(Tuple{typeof(RtcAgent),Aeron.Client,ClockType})
    precompile(Tuple{typeof(RtcAgent),ClockType})

    # Agent interface methods
    precompile(Tuple{typeof(Agent.name),AgentType})
    precompile(Tuple{typeof(Agent.on_start),AgentType})
    precompile(Tuple{typeof(Agent.on_close),AgentType})
    precompile(Tuple{typeof(Agent.on_error),AgentType,Exception})
    precompile(Tuple{typeof(Agent.on_error),AgentType,Any})
    precompile(Tuple{typeof(Agent.do_work),AgentType})

    # Communication setup
    precompile(Tuple{typeof(setup_communications!),AgentType,CommunicationResources})
end

# Call precompile function
_precompile()
