"""
Test suite for Timer system functionality.
Tests timer scheduling, cancellation, and polling.
"""
function test_timers(client)
    @testset "Timer Basic Operations" begin
        clock = CachedEpochClock(EpochClock())
        timers = PolledTimer(clock)
        
        # Test initial state
        @test length(timers) == 0
        @test isempty(timers)
        
        # Test timer scheduling
        timer_id = schedule!(timers, 1_000_000, :TestEvent)
        @test timer_id > 0
        @test length(timers) == 1
        @test !isempty(timers)
        
        # Test timer cancellation
        cancel!(timers, timer_id)
        @test length(timers) == 0
        @test isempty(timers)
    end
    
    @testset "Timer Integration with Agent" begin
        clock = CachedEpochClock(EpochClock())
        properties = Properties(clock)
        comms = CommunicationResources(client, properties)
        agent = RtcAgent(client, comms, properties, clock)
        
        # Test that agent has timer system
        @test !isnothing(agent.timers)
        @test agent.timers isa PolledTimer
        
        # Test timer polling (should not error)
        @test_nowarn timer_poller(agent)
    end
    
    # Additional timer tests would go here
    # - Timer firing tests (with clock mocking)
    # - Multiple timer management
    # - Timer event dispatch integration
end
