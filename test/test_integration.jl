# Integration test suite for full agent workflows.
# Tests complete agent lifecycle, property publishing workflows, and error scenarios.
function test_integration(client)
    @testset "Complete Agent Lifecycle" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test full lifecycle from creation to shutdown
        # Note: RtcAgent doesn't have a public state field, test behavior instead
        
        # Open agent
        Agent.on_start(agent)
        @test agent.properties !== nothing
        
        # Test agent work processing directly (without AgentRunner threading)
        work_count = Agent.do_work(agent)
        @test work_count isa Int
        
        # Close agent
        Agent.on_close(agent)
    end
    
    @testset "Property Publishing Workflow" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        Agent.on_start(agent)
        
        # Test that properties are accessible
        @test agent.properties !== nothing
        
        # Test strategy processing works using Agent API
        @test_nowarn Agent.do_work(agent)
        
        Agent.on_close(agent)
    end
    
    @testset "Error Handling Workflows" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test that invalid stream indices throw proper errors
        @test_throws StreamNotFoundError get_publication(agent, 999)
        
        Agent.on_start(agent)
        
        # Test that multiple start calls are handled gracefully
        @test_nowarn Agent.on_start(agent)
        
        Agent.on_close(agent)
        
        Agent.on_close(agent)
    end
    
    @testset "Multi-Agent Scenarios" begin
        # Test multiple agents can coexist
        clock1 = CachedEpochClock(EpochClock())
        properties1 = Properties(clock1)
        comms1 = CommunicationResources(client, properties1)
        agent1 = RtcAgent(client, comms1, properties1, clock1)
        clock2 = CachedEpochClock(EpochClock())
        properties2 = Properties(clock2)
        comms2 = CommunicationResources(client, properties2)
        agent2 = RtcAgent(client, comms2, properties2, clock2)
        
        Agent.on_start(agent1)
        Agent.on_start(agent2)
        
        # Both agents should be independent and have properties
        @test agent1.properties !== nothing
        @test agent2.properties !== nothing
        @test agent1.properties !== agent2.properties  # Different instances
        
        Agent.on_close(agent1)
        Agent.on_close(agent2)
    end
    
    @testset "Performance Validation" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        Agent.on_start(agent)
        
        # Measure allocation-free processing
        # First run to warm up
        Agent.do_work(agent)
        
        # Actual measurement
        allocations = @allocated Agent.do_work(agent)
        @test allocations == 0  # Agent work should be allocation-free
        
        Agent.on_close(agent)
    end
end
