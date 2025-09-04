"""
Test suite for communication layer functionality.
Tests basic communication setup without requiring actual Aeron streams.
"""
function test_communications(client)
    @testset "Message Publishing" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        Agent.on_start(agent)  # Initialize adapters
        
        # Test that basic agent setup works
        @test !isnothing(agent.properties)
        @test agent.properties[:Name] isa String
        
        # Test that we can access agent properties
        @test haskey(agent.properties, :Name)
        @test haskey(agent.properties, :NodeId) 
        @test haskey(agent.properties, :HeartbeatPeriodNs)
        
        Agent.on_close(agent)
    end
    
    @testset "Communication Setup" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)

        # Test communication resources creation
        comms = TestService.CommunicationResources(client, properties)
        @test !isnothing(comms)
        @test comms isa TestService.CommunicationResources
        @test !isnothing(comms.status_stream)
        @test !isnothing(comms.control_stream)
        @test comms.input_streams isa Vector
        @test comms.output_streams isa Vector
        
        # Test agent construction with dependency injection
        agent = RtcAgent(comms, properties, clock)
        @test !isnothing(agent)
        @test !isnothing(agent.properties)
        @test agent.comms === comms
        
        # Test agent lifecycle
        @test_nowarn Agent.on_start(agent)
        @test_nowarn Agent.on_close(agent)
    end
end
