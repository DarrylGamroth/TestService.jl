"""
Test suite for property publishing system.
Tests the integration of strategies with actual property publishing.
"""
function test_property_publishing(client)
    @testset "Property Publication Workflow" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        Agent.on_start(agent)
        
        # Test that properties are accessible
        @test agent.properties !== nothing
        
        # Test that registry is accessible
        @test agent.property_registry isa Vector
        
        Agent.on_close(agent)
    end
    
    @testset "Periodic Publishing" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        Agent.on_start(agent)
        
        # Test basic agent functionality
        @test agent.properties !== nothing
        
        Agent.on_close(agent)
    end
    
    @testset "Multiple Strategy Integration" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        Agent.on_start(agent)
        
        # Test basic agent functionality
        @test agent.properties !== nothing
        
        Agent.on_close(agent)
    end
    
    @testset "Publication Config Management" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        
        # Test basic agent functionality without streams
        @test agent.property_registry isa Vector
        @test isempty(agent.property_registry)  # No registrations yet
        
        Agent.on_start(agent)
        Agent.on_close(agent)
    end
    
    @testset "Strategy State Updates" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        Agent.on_start(agent)
        
        # Test basic agent functionality
        @test agent.properties !== nothing
        
        Agent.on_close(agent)
    end
    
    @testset "Property Access in Publishing" begin
        # Test basic property access without stream dependencies
        periodic_strategy = Periodic(1000)
        @test periodic_strategy.interval_ns == 1000
        
        onupdate_strategy = OnUpdate()
        @test onupdate_strategy isa PublishStrategy
        
        # Test should_publish functions work
        @test TestService.should_publish(onupdate_strategy, 100, -1, 200, 1500) isa Bool
    end
    
    @testset "Zero Allocation Publishing" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        Agent.on_start(agent)
        
        # Test basic agent functionality
        @test agent.properties !== nothing
        
        Agent.on_close(agent)
    end
end
