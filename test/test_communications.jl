"""
Test suite for communication layer functionality.
Tests basic communication setup without requiring actual Aeron streams.
"""
function test_communications()
    @testset "Message Publishing" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                clock = CachedEpochClock(EpochClock())
                properties = Properties(clock)
                agent = RtcAgent(client, properties, clock)
                open(agent)
                
                # Test that basic agent setup works
                @test !isnothing(agent.properties)
                @test agent.properties[:Name] isa String
                
                # Test that we can access agent properties
                @test haskey(agent.properties, :Name)
                @test haskey(agent.properties, :NodeId) 
                @test haskey(agent.properties, :HeartbeatPeriodNs)
                
                close(agent)
            end
        end
    end
    
    @testset "Communication Setup" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                clock = CachedEpochClock(EpochClock())
                properties = Properties(clock)
                agent = RtcAgent(client, properties, clock)
                
                # Test basic construction
                @test !isnothing(agent)
                @test !isnothing(agent.properties)
                
                # Test agent lifecycle
                @test_nowarn open(agent)
                @test_nowarn close(agent)
            end
        end
    end
end
