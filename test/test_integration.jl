# Integration test suite for full agent workflows.
# Tests complete agent lifecycle, property publishing workflows, and error scenarios.
function test_integration()
    @testset "Complete Agent Lifecycle" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                
                # Test full lifecycle from creation to shutdown
                # Note: RtcAgent doesn't have a public state field, test behavior instead
                
                # Open agent
                open(agent)
                @test agent.properties !== nothing
                
                # Test agent work processing directly (without AgentRunner threading)
                work_count = Agent.do_work(agent)
                @test work_count isa Int
                
                # Close agent
                close(agent)
            end
        end
    end
    
    @testset "Property Publishing Workflow" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test that properties are accessible
                @test agent.properties !== nothing
                
                # Test strategy processing works using Agent API
                @test_nowarn Agent.do_work(agent)
                
                close(agent)
            end
        end
    end
    
    @testset "Error Handling Workflows" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                
                # Test state transition errors by trying to use agent before opening
                @test_throws CommunicationNotInitializedError get_publication(agent, 1)
                
                open(agent)
                
                # Test that opening twice throws an error
                @test_throws AgentStateError open(agent)
                
                close(agent)
            end
        end
    end
    
    @testset "Multi-Agent Scenarios" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                # Test multiple agents can coexist
                agent1 = RtcAgent(client)
                agent2 = RtcAgent(client)
                
                open(agent1)
                open(agent2)
                
                # Both agents should be independent and have properties
                @test agent1.properties !== nothing
                @test agent2.properties !== nothing
                @test agent1.properties !== agent2.properties  # Different instances
                
                close(agent1)
                close(agent2)
            end
        end
    end
    
    @testset "Performance Validation" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Measure allocation-free processing
                # First run to warm up
                Agent.do_work(agent)
                
                # Actual measurement
                allocations = @allocated Agent.do_work(agent)
                @test allocations == 0  # Agent work should be allocation-free
                
                close(agent)
            end
        end
    end
end
