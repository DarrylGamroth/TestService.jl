# Test suite for exception handling system.
# Tests custom exception types and error handling workflows.
function test_exceptions(client)
    @testset "Exception Handling Integration" begin
        # Test that exceptions are thrown in proper error scenarios
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test that proper errors are thrown for invalid operations
        # With the new architecture, communications are always initialized
        # so we test for invalid stream indices instead
        @test_throws StreamNotFoundError get_publication(agent, 999)
        
        Agent.on_start(agent)
        # Agent.on_start should be idempotent or add state checking in future
        # For now, test that multiple calls don't crash
        @test_nowarn Agent.on_start(agent)   
        
        Agent.on_close(agent)
    end
    
    @testset "Error Message Quality" begin
        # Basic test that error handling works without exposing internal types
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
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
