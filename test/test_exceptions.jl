# Test suite for exception handling system.
# Tests custom exception types and error handling workflows.
function test_exceptions()
    @testset "Exception Handling Integration" begin
        # Test that exceptions are thrown in proper error scenarios
        Aeron.Context() do context
            Aeron.Client(context) do client
                clock = CachedEpochClock(EpochClock())
                properties = Properties(clock)
                agent = RtcAgent(client, properties, clock)
                
                # Test that proper errors are thrown for invalid operations
                @test_throws CommunicationNotInitializedError get_publication(agent, 1)
                
                open(agent)
                @test_throws AgentStateError open(agent)   # Can't open when already open
                
                close(agent)
            end
        end
    end
    
    @testset "Error Message Quality" begin
        # Basic test that error handling works without exposing internal types
        Aeron.Context() do context
            Aeron.Client(context) do client
                clock = CachedEpochClock(EpochClock())
                properties = Properties(clock)
                agent = RtcAgent(client, properties, clock)
                
                # This should throw an informative error
                try
                    start(agent)  # Invalid state transition
                    @test false  # Should have thrown an exception
                catch e
                    @test e isa Exception
                    @test !isempty(string(e))  # Error message should not be empty
                end
                
                close(agent)
            end
        end
    end
end
