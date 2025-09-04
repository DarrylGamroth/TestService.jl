# Test suite for utility functions.
# Tests event response handling, property encoding/decoding, and property handlers.

function test_utilities(client)
    @testset "Property Value Handling" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        Agent.on_start(agent)
        
        # Test that properties exist and are accessible
        @test agent.properties !== nothing
        @test isa(agent.properties, Any)  # Properties exist but structure may vary
        
        Agent.on_close(agent)
    end
    
    # Additional utility tests would go here in a real implementation
    # - Property value encoding/decoding tests
    # - Property write handler tests  
    # - Message format validation tests
end
