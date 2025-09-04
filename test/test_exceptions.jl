# Test suite for exception handling system.
# Tests custom exception types and error handling workflows.
function test_exceptions(client) 
    @testset "Error Message Quality" begin
        # Basic test that error handling works without exposing internal types
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        
        # This should throw an informative error
        try
            start(agent)  # Invalid state transition
            @test false  # Should have thrown an exception
        catch e
            @test e isa Exception
            @test !isempty(string(e))  # Error message should not be empty
        end
        
        Agent.on_close(agent)
    end
end
