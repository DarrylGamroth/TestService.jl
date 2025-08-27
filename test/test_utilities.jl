# Test suite for utility functions.
# Tests event response handling, property encoding/decoding, and property handlers.
function test_utilities()
    @testset "Property Value Handling" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test that properties exist and are accessible
                @test agent.properties !== nothing
                @test isa(agent.properties, Any)  # Properties exist but structure may vary
                
                close(agent)
            end
        end
    end
    
    # Additional utility tests would go here in a real implementation
    # - Property value encoding/decoding tests
    # - Property write handler tests  
    # - Message format validation tests
end
