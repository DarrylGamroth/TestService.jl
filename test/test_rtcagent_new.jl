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
        @test agent.correlation_id == 0
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
        @test !isempty(agent.input_adapters)
        @test all(adapter -> adapter isa InputStreamAdapter, agent.input_adapters)
        
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
        @test !isempty(agent.input_adapters)
        
        # Test Agent.do_work
        work_count = Agent.do_work(agent)
        @test work_count isa Int
        @test work_count >= 0
        
        # Test Agent.on_close - cleans up adapters
        result = Agent.on_close(agent)
        @test result === nothing
        @test agent.control_adapter === nothing
        @test isempty(agent.input_adapters)
    end
    
    @testset "Event Dispatch" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test dispatching unknown event
        unknown_event = :UnknownEvent
        @test TestService.dispatch_event(agent, unknown_event) == false
        
        # Test dispatching known event would return true if implemented
        @test TestService.dispatch_event(agent, :StopEvent) == false  # Not implemented yet
    end
    
    @testset "Property Registry Management" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test adding property to registry
        register_property!(agent, :TestProperty, OnUpdate())
        @test haskey(agent.property_registry, :TestProperty)
        @test agent.property_registry[:TestProperty] isa PropertyRegistration
        
        # Test that registered property has correct strategy
        reg = agent.property_registry[:TestProperty]
        @test reg.strategy isa PublishStrategy
        
        # Test removing property from registry
        unregister_property!(agent, :TestProperty)
        @test !haskey(agent.property_registry, :TestProperty)
        
        # Test unregistering non-existent property doesn't error
        @test_nowarn unregister_property!(agent, :NonExistentProperty)
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
        @test timer_work(agent) isa Int
        @test status_heartbeat(agent) isa Int
        @test property_publisher(agent) isa Int
        
        # All should return 0 in test environment (no actual work)
        @test control_poller(agent) == 0
        @test input_poller(agent) == 0
        @test timer_work(agent) >= 0  # May have timer work
        @test status_heartbeat(agent) >= 0  # May publish heartbeat
        @test property_publisher(agent) >= 0  # May publish properties
        
        Agent.on_close(agent)
    end
end
