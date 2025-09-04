using TestService
using Aeron
using Clocks

"""
Test suite for stream adapter functionality.
Tests ControlStreamAdapter and InputStreamAdapter operations.
"""
function test_adapters(client)
    @testset "ControlStreamAdapter" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        
        # Test adapter creation
        adapter = TestService.ControlStreamAdapter(comms.control_stream, agent)
        @test adapter isa TestService.ControlStreamAdapter
        @test !isnothing(adapter.subscription)
        @test !isnothing(adapter.assembler)
        
        # Test polling (should return 0 in empty test environment)
        fragments_read = TestService.poll(adapter, 10)
        @test fragments_read isa Int
        @test fragments_read == 0
    end
    
    @testset "InputStreamAdapter" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        
        # Test single adapter creation and operation
        if !isempty(comms.input_streams)
            adapter = TestService.InputStreamAdapter(comms.input_streams[1], agent)
            @test adapter isa TestService.InputStreamAdapter
            @test !isnothing(adapter.subscription)
            @test !isnothing(adapter.assembler)
            
            # Test polling (should return 0 in empty test environment)
            fragments_read = TestService.poll(adapter, 10)
            @test fragments_read isa Int
            @test fragments_read == 0
        end
        
        # Test multiple adapter creation and polling
        adapters = TestService.InputStreamAdapter[]
        for stream in comms.input_streams
            push!(adapters, TestService.InputStreamAdapter(stream, agent))
        end
        
        # Test vector polling
        total_fragments = TestService.poll(adapters, 10)
        @test total_fragments isa Int
        @test total_fragments == 0
        
        # Test empty adapter vector
        empty_adapters = TestService.InputStreamAdapter[]
        @test TestService.poll(empty_adapters, 10) == 0
    end
    
    @testset "CommunicationResources" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        
        # Test construction
        comms = TestService.CommunicationResources(client, properties)
        @test comms isa TestService.CommunicationResources
        @test !isnothing(comms.status_stream)
        @test !isnothing(comms.control_stream)
        @test comms.input_streams isa Vector{Aeron.Subscription}
        @test comms.output_streams isa Vector{Aeron.ExclusivePublication}
        
        # Test that streams are created according to properties
        @test comms.status_stream isa Aeron.ExclusivePublication
        @test comms.control_stream isa Aeron.Subscription
        
        # Test that streams are properly initialized (not closed)
        @test isopen(comms.status_stream)
        @test isopen(comms.control_stream)
        
        # Test close functionality
        @test_nowarn close(comms)
    end
    
    @testset "Agent Adapter Integration" begin
        clock = CachedEpochClock(EpochClock())
        properties = TestService.PropertyStore.Properties(clock)
        comms = TestService.CommunicationResources(client, properties)
        agent = RtcAgent(comms, properties, clock)
        
        # Test initial state
        @test agent.control_adapter === nothing
        @test isempty(agent.input_adapters)
        
        # Test adapter creation via Agent.on_start
        Agent.on_start(agent)
        @test !isnothing(agent.control_adapter)
        @test agent.control_adapter isa TestService.ControlStreamAdapter
        @test length(agent.input_adapters) == length(comms.input_streams)
        @test all(adapter -> adapter isa TestService.InputStreamAdapter, agent.input_adapters)
        
        # Test adapter polling via agent pollers
        @test TestService.control_poller(agent) == 0
        @test TestService.input_poller(agent) == 0
        
        # Test adapter cleanup via Agent.on_close
        Agent.on_close(agent)
        @test agent.control_adapter === nothing
        @test isempty(agent.input_adapters)
    end
end
