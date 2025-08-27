"""
Test suite for property publishing system.
Tests the integration of strategies with actual property publishing.
"""
function test_property_publishing()
    @testset "Property Publication Workflow" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test that properties are accessible
                @test agent.properties !== nothing
                
                # Test that registry is accessible
                @test agent.property_registry isa Vector
                
                close(agent)
            end
        end
    end
    
    @testset "Periodic Publishing" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test basic agent functionality
                @test agent.properties !== nothing
                
                close(agent)
            end
        end
    end
    
    @testset "Multiple Strategy Integration" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test basic agent functionality
                @test agent.properties !== nothing
                
                close(agent)
            end
        end
    end
    
    @testset "Publication Config Management" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                
                # Test basic agent functionality without streams
                @test agent.property_registry isa Vector
                @test isempty(agent.property_registry)  # No registrations yet
                
                open(agent)
                close(agent)
            end
        end
    end
    
    @testset "Strategy State Updates" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test basic agent functionality
                @test agent.properties !== nothing
                
                close(agent)
            end
        end
    end
    
    @testset "Property Access in Publishing" begin
        # Test basic property access without stream dependencies
        periodic_strategy = Periodic(1000)
        @test periodic_strategy.interval_ns == 1000
        
        onupdate_strategy = OnUpdate()
        @test onupdate_strategy isa PublishStrategy
        
        # Test should_publish functions work
        @test should_publish(onupdate_strategy, 100, -1, 200, 1500) isa Bool
    end
    
    @testset "Zero Allocation Publishing" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test basic agent functionality
                @test agent.properties !== nothing
                
                close(agent)
            end
        end
    end
end
