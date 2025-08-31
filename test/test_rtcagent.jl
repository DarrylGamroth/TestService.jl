"""
Test suite for RtcAgent core functionality.
Tests agent construction, lifecycle, and integration with Agent.jl framework.
"""
function test_rtcagent(client)
    @testset "RtcAgent Construction" begin
        # Test basic construction with dependency injection
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        @test agent isa RtcAgent
        @test agent.client === client
        @test agent.source_correlation_id == 0
        @test agent.position_ptr[] == 0
        @test agent.comms === comms
        @test !isnothing(agent.clock)
        @test !isnothing(agent.properties)
        @test !isnothing(agent.id_gen)
        @test !isnothing(agent.timers)
        @test isempty(agent.property_registry)
        @test agent.control_adapter === nothing  # Not yet initialized
        @test isempty(agent.input_adapters)      # Not yet initialized
        
        # Test construction with specific clock
        clock2 = CachedEpochClock(EpochClock())
        properties2 = Properties(clock2)
        comms2 = CommunicationResources(client, properties2)
        agent2 = RtcAgent(client, comms2, properties2, clock2)
        @test agent2.clock === clock2
    end
    
    @testset "Communication Lifecycle" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test initial state - communication resources are already created
        @test !isnothing(agent.comms)
        @test agent.comms isa CommunicationResources
        @test agent.control_adapter === nothing
        @test isempty(agent.input_adapters)
        
        # Test that Agent.on_start creates adapters
        Agent.on_start(agent)
        @test !isnothing(agent.control_adapter)
        @test agent.control_adapter isa ControlStreamAdapter
        # NOTE: input_adapters might be empty if no input streams are configured
        @test agent.input_adapters isa Vector{InputStreamAdapter}
        
        # Test that Agent.on_close clears adapters and closes resources
        Agent.on_close(agent)
        @test agent.control_adapter === nothing
        @test isempty(agent.input_adapters)
    end
    
    @testset "Agent Interface Implementation" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test Agent.name
        name = Agent.name(agent)
        @test name isa String
        @test name == agent.properties[:Name]
        
        # Test Agent.on_start - creates adapters
        result = Agent.on_start(agent)
        @test result === nothing
        @test !isnothing(agent.control_adapter)
        @test agent.input_adapters isa Vector{InputStreamAdapter}
        
        # Test Agent.do_work
        work_count = Agent.do_work(agent)
        @test work_count isa Int
        @test work_count >= 0
        
        # Test Agent.on_close - cleans up adapters
        Agent.on_close(agent)
        @test agent.control_adapter === nothing
        @test isempty(agent.input_adapters)
    end
    
    @testset "Dispatch System" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test dispatch! function exists and handles events
        @test_nowarn dispatch!(agent, :TestEvent)
        @test_nowarn dispatch!(agent, :AnotherEvent, "test message")
    end
    
    @testset "Property Registry Management" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test property registry operations
        @test isempty(agent.property_registry)
        @test !isregistered(agent, :TestProperty)
        
        # Test that we can access registry functions
        @test list(agent) == []
        @test empty!(agent) == 0  # No registrations to clear
    end
    
    @testset "Error Handling" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test that agent handles errors gracefully
        @test_nowarn Agent.on_start(agent)
        @test_nowarn Agent.do_work(agent)
        @test_nowarn Agent.on_close(agent)
        
        # Test multiple start/close cycles
        @test_nowarn Agent.on_start(agent)
        @test_nowarn Agent.on_close(agent)
        @test_nowarn Agent.on_start(agent)
        @test_nowarn Agent.on_close(agent)
    end
    
    @testset "Work Loop Components" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        Agent.on_start(agent)
        
        # Test individual work components
        @test control_poller(agent) isa Int
        @test input_poller(agent) isa Int
        @test timer_poller(agent) isa Int
        @test property_poller(agent) isa Int
        
        # All should return 0 in test environment (no actual work)
        @test control_poller(agent) == 0
        @test input_poller(agent) == 0
        @test timer_poller(agent) >= 0  # May have timer work
        @test property_poller(agent) >= 0  # May publish properties
        
        Agent.on_close(agent)
    end
end
