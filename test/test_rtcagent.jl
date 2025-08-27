"""
Test suite for RtcAgent core functionality.
Tests agent construction, lifecycle, and integration with Agent.jl framework.
"""
function test_rtcagent()
    @testset "RtcAgent Construction" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                # Test basic construction
                agent = RtcAgent(client)
                @test agent isa RtcAgent
                @test agent.client === client
                @test agent.correlation_id == 0
                @test agent.position_ptr[] == 0
                @test agent.comms === nothing
                @test !isnothing(agent.clock)
                @test !isnothing(agent.properties)
                @test !isnothing(agent.id_gen)
                @test !isnothing(agent.timers)
                @test isempty(agent.property_registry)
                
                # Test construction with specific clock
                clock = CachedEpochClock(EpochClock())
                agent2 = RtcAgent(client, clock)
                @test agent2.clock === clock
            end
        end
    end
    
    @testset "Communication Lifecycle" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                
                # Test initial state
                @test !isopen(agent)
                @test agent.comms === nothing
                
                # Test opening communications
                open(agent)
                @test isopen(agent)
                @test !isnothing(agent.comms)
                @test agent.comms isa CommunicationResources
                
                # Test that opening already open agent throws error
                @test_throws AgentStateError open(agent)
                
                # Test closing communications
                close(agent)
                @test !isopen(agent)
                @test agent.comms === nothing
                
                # Test that closing already closed agent is safe
                close(agent)  # Should not throw
                @test !isopen(agent)
            end
        end
    end
    
    @testset "Agent Interface Implementation" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                
                # Test Agent.name
                name = Agent.name(agent)
                @test name isa String
                @test name == agent.properties[:Name]
                
                # Test Agent.on_start
                result = Agent.on_start(agent)
                @test result === nothing
                @test isopen(agent)  # Should have opened communications
                
                # Test Agent.do_work
                work_count = Agent.do_work(agent)
                @test work_count isa Int
                @test work_count >= 0
                
                # Test Agent.on_close
                Agent.on_close(agent)
                @test !isopen(agent)  # Should have closed communications
                
                # Test Agent.on_error
                test_error = ArgumentError("test error")
                # Should not throw, just log the error
                @test_nowarn Agent.on_error(agent, test_error)
            end
        end
    end
    
    @testset "Event Dispatch" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test basic dispatch
                @test_nowarn dispatch!(agent, :TestEvent, nothing)
                @test_nowarn dispatch!(agent, :TestEvent, 42)
                @test_nowarn dispatch!(agent, :TestEvent, "test")
                
                # Test that correlation_id gets updated during message dispatch
                # (This would be tested with actual message objects in integration tests)
            end
        end
    end
    
    @testset "Property Registry Management" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test initial empty registry
                @test isempty(agent.property_registry)
                @test list(agent) == []
                @test empty!(agent) == 0
                
                # Test basic registry functionality without requiring actual streams
                @test !isregistered(agent, :NodeId)
                @test !isregistered(agent, :Name)
                
                # Test that we can query the registry
                registrations = list(agent)
                @test registrations isa Vector
                @test length(registrations) == 0  # No registrations initially
                
                close(agent)
            end
        end
    end
    
    @testset "Error Handling" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                
                # Test errors when communications not open
                @test_throws CommunicationNotInitializedError get_publication(agent, 1)
                @test_throws CommunicationNotInitializedError register!(agent, :NodeId, 1, OnUpdate())
                
                open(agent)
                
                # Test invalid stream index
                @test_throws StreamNotFoundError get_publication(agent, 999)
                @test_throws StreamNotFoundError register!(agent, :NodeId, 999, OnUpdate())
                
                # Test unregistering non-existent property
                @test unregister!(agent, :NonExistent) == 0
                @test unregister!(agent, :NonExistent, 1) == 0
            end
        end
    end
    
    @testset "Work Loop Components" begin
        Aeron.Context() do context
            Aeron.Client(context) do client
                agent = RtcAgent(client)
                open(agent)
                
                # Test individual pollers
                @test input_poller(agent) isa Int
                @test control_poller(agent) isa Int
                @test property_poller(agent) isa Int
                @test timer_poller(agent) isa Int
                
                # All should return 0 in empty test environment
                @test input_poller(agent) == 0
                @test control_poller(agent) == 0
                @test property_poller(agent) == 0
                @test timer_poller(agent) == 0
            end
        end
    end
end
