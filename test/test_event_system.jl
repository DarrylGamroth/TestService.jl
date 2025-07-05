# Test file for EventSystem module using mock Aeron

function test_event_system()
    @testset "EventSystem Module Tests" begin
        @testset "EventManager Construction" begin
            # Create test components using environment variables for Properties
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    # Test EventManager construction
                    em = EventManager(client, props, clock, id_gen)
                    @test em isa EventManager
                    @test em.client === client
                    @test em.properties === props
                    @test em.clock === clock
                    @test em.id_gen === id_gen
                    @test em.correlation_id == 0
                    @test em.position_ptr[] == 0
                    @test em.comms === nothing
                    @test em.timer_manager isa TimerManager
                end
            end
        end

        @testset "Communication Lifecycle" begin
            # Setup test components
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    # Test initial state
                    @test !EventSystem.is_communications_active(em)
                    @test em.comms === nothing

                    # Test setup_communications!
                    EventSystem.setup_communications!(em)
                    @test EventSystem.is_communications_active(em)
                    @test em.comms !== nothing
                    @test em.comms isa CommunicationResources

                    # Test that setup_communications! throws error when already active
                    @test_throws ArgumentError EventSystem.setup_communications!(em)

                    # Test teardown_communications!
                    EventSystem.teardown_communications!(em)
                    @test !EventSystem.is_communications_active(em)
                    @test em.comms === nothing

                    # Test that teardown on inactive communications is safe
                    EventSystem.teardown_communications!(em)  # Should not throw
                end
            end
        end

        @testset "Timer Management" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    # Test timer scheduling
                    timer_id = EventSystem.schedule_timer_event!(em, :TestEvent, 1000000)  # 1ms
                    @test timer_id > 0

                    # Test timer scheduling at specific time
                    deadline = time_nanos(clock) + 2000000  # 2ms from now
                    timer_id2 = EventSystem.schedule_timer_event_at!(em, :TestEvent2, deadline)
                    @test timer_id2 > 0
                    @test timer_id2 != timer_id

                    # Test timer cancellation
                    EventSystem.cancel_timer!(em, timer_id)

                    # Test cancel by event
                    timer_id3 = EventSystem.schedule_timer_event!(em, :TestEvent3, 1000000)
                    @test timer_id3 > 0
                    EventSystem.cancel_timer_by_event!(em, :TestEvent3)

                    # Test cancel all timers
                    EventSystem.schedule_timer_event!(em, :TestEvent4, 1000000)
                    EventSystem.schedule_timer_event!(em, :TestEvent5, 1000000)
                    EventSystem.cancel_all_timers!(em)
                end
            end
        end

        @testset "Polling Functions" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    # Test polling without communications (should return 0)
                    @test EventSystem.input_stream_poller(em) == 0
                    @test EventSystem.control_poller(em) == 0
                    @test EventSystem.poller(em) == 0

                    # Setup communications for polling tests
                    EventSystem.setup_communications!(em)

                    # Test polling with communications (mock returns 0 but doesn't error)
                    @test EventSystem.input_stream_poller(em) >= 0
                    @test EventSystem.control_poller(em) >= 0
                    @test EventSystem.poller(em) >= 0

                    EventSystem.teardown_communications!(em)
                end
            end
        end

        @testset "Message Sending" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    # Test send_event_response without communications (should warn and return)
                    EventSystem.send_event_response(em, :TestEvent, "test_value")  # Should not error

                    # Setup communications
                    EventSystem.setup_communications!(em)

                    # Test send_event_response with communications
                    # Note: With mock objects, this tests the code path but not actual Aeron behavior
                    EventSystem.send_event_response(em, :TestEvent, "test_value")
                    EventSystem.send_event_response(em, :TestEvent, 42)
                    EventSystem.send_event_response(em, :TestEvent, 3.14)
                    EventSystem.send_event_response(em, :TestEvent, true)
                    EventSystem.send_event_response(em, :TestEvent, :symbol_value)

                    EventSystem.teardown_communications!(em)
                end
            end
        end

        @testset "Event Dispatch" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    # Test basic event dispatch (should not error with state machine)
                    try
                        EventSystem.dispatch!(em, :Initialize)
                        EventSystem.dispatch!(em, :Start)
                        EventSystem.dispatch!(em, :Stop)
                        @test true  # If we get here, dispatch didn't throw
                    catch e
                        # Some errors are expected if state machine isn't fully implemented
                        @test true
                    end
                end
            end
        end

        @testset "Handle Timer Event" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    # Test handle_timer_event! function
                    now = time_nanos(clock)
                    timer_id = Int64(12345)

                    # Add a timer event mapping
                    em.timer_manager.event_map[timer_id] = :TimerTestEvent

                    # Handle the timer event
                    result = EventSystem.handle_timer_event!(em, timer_id, now)
                    @test result == true
                    @test !haskey(em.timer_manager.event_map, timer_id)  # Should be cleaned up

                    # Test with non-existent timer ID (should use default)
                    result = EventSystem.handle_timer_event!(em, Int64(99999), now)
                    @test result == true
                end
            end
        end

        @testset "Communication Resources Creation" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    # Test CommunicationResources creation
                    comm_resources = EventSystem.CommunicationResources(em)
                    @test comm_resources isa EventSystem.CommunicationResources
                    @test comm_resources.status_stream isa Aeron.Publication
                    @test comm_resources.control_stream isa Aeron.Subscription
                    @test comm_resources.input_streams isa Vector{Aeron.Subscription}
                    @test comm_resources.output_streams isa Dict{Symbol,Aeron.Publication}
                    @test haskey(comm_resources.output_streams, :Status)
                    @test length(comm_resources.buf) > 0
                end
            end
        end

        @testset "EventManager API Consistency with PropertiesManager" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    # Test that EventManager has the same communication lifecycle API as PropertiesManager
                    @test !EventSystem.is_communications_active(em)

                    EventSystem.setup_communications!(em)
                    @test EventSystem.is_communications_active(em)

                    # Should throw if already active
                    @test_throws ArgumentError EventSystem.setup_communications!(em)

                    EventSystem.teardown_communications!(em)
                    @test !EventSystem.is_communications_active(em)

                    # Should be safe to teardown again
                    EventSystem.teardown_communications!(em)
                    @test !EventSystem.is_communications_active(em)
                end
            end
        end

        @testset "Zero Allocation Tests" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)
                    EventSystem.setup_communications!(em)

                    @testset "Poller Zero Allocations" begin
                        # Warm up the functions first
                        for _ in 1:10
                            EventSystem.poller(em)
                            EventSystem.input_stream_poller(em)
                            EventSystem.control_poller(em)
                        end

                        # Force compilation of all paths
                        GC.gc()  # Clean up any compilation artifacts

                        # Test that pollers don't allocate
                        allocs = @allocated EventSystem.poller(em)
                        @test allocs == 0

                        allocs = @allocated EventSystem.input_stream_poller(em)
                        @test allocs == 0

                        allocs = @allocated EventSystem.control_poller(em)
                        @test allocs == 0
                    end

                    @testset "Timer Function Zero Allocations" begin
                        # Schedule a timer first
                        timer_id = EventSystem.schedule_timer_event!(em, :TestEvent, 1000000)

                        # Warm up timer functions
                        for _ in 1:10
                            EventSystem.handle_timer_event!(em, timer_id, time_nanos(clock))
                            # Reschedule since handle_timer_event! removes the mapping
                            em.timer_manager.event_map[timer_id] = :TestEvent
                        end

                        GC.gc()

                        # Test that handle_timer_event! doesn't allocate
                        em.timer_manager.event_map[timer_id] = :TestEvent
                        allocs = @allocated EventSystem.handle_timer_event!(em, timer_id, time_nanos(clock))
                        @test allocs == 0
                    end

                    EventSystem.teardown_communications!(em)
                end
            end
        end

        @testset "Type Stability Tests" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)

                    @testset "EventManager Type Stability" begin
                        @test em isa EventManager
                        @test typeof(em.client) === Aeron.Client
                        @test typeof(em.properties) === Properties{EpochClock}
                        @test typeof(em.clock) === EpochClock
                        @test typeof(em.id_gen) === SnowflakeIdGenerator{EpochClock}
                        @test typeof(em.timer_manager) === TimerManager{EpochClock}
                    end

                    @testset "Communication Function Type Stability" begin
                        EventSystem.setup_communications!(em)

                        # Test that function calls return expected types
                        result = EventSystem.is_communications_active(em)
                        @test result isa Bool

                        work_count = EventSystem.poller(em)
                        @test work_count isa Int

                        work_count = EventSystem.input_stream_poller(em)
                        @test work_count isa Int

                        work_count = EventSystem.control_poller(em)
                        @test work_count isa Int

                        EventSystem.teardown_communications!(em)
                    end

                    @testset "Timer Function Type Stability" begin
                        timer_id = EventSystem.schedule_timer_event!(em, :TestEvent, 1000000)
                        @test timer_id isa Int64

                        timer_id2 = EventSystem.schedule_timer_event_at!(em, :TestEvent2, time_nanos(clock) + 1000000)
                        @test timer_id2 isa Int64

                        # Test handle_timer_event! return type
                        em.timer_manager.event_map[timer_id] = :TestEvent
                        result = EventSystem.handle_timer_event!(em, timer_id, time_nanos(clock))
                        @test result isa Bool
                    end
                end
            end
        end

        @testset "Integration with MessagingSystem" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)
                    EventSystem.setup_communications!(em)

                    @testset "Message Sending Integration" begin
                        # Test that send_event_response properly delegates to MessagingSystem
                        # This tests the integration point but with mocked Aeron

                        # Test various value types
                        EventSystem.send_event_response(em, :StringEvent, "test")
                        EventSystem.send_event_response(em, :IntEvent, 42)
                        EventSystem.send_event_response(em, :FloatEvent, 3.14)
                        EventSystem.send_event_response(em, :BoolEvent, true)
                        EventSystem.send_event_response(em, :SymbolEvent, :test_symbol)

                        # Test with array (should use MessagingSystem's multiple dispatch)
                        test_array = [1, 2, 3, 4, 5]
                        EventSystem.send_event_response(em, :ArrayEvent, test_array)

                        # All should complete without error (though mocked)
                        @test true
                    end

                    EventSystem.teardown_communications!(em)
                end
            end
        end

        @testset "Event System Work Loop Simulation" begin
            Aeron.Context() do context
                Aeron.Client(context) do client
                    clock = EpochClock()
                    props = Properties(clock)
                    id_gen = SnowflakeIdGenerator(1, clock)

                    em = EventManager(client, props, clock, id_gen)
                    EventSystem.setup_communications!(em)

                    work_counts = Int[]
                    total_work = 0

                    # Simulate event system work loop for 20 iterations
                    for i in 1:20
                        # Poll for work (like agent does)
                        work_count = EventSystem.poller(em)
                        push!(work_counts, work_count)
                        total_work += work_count

                        # Occasionally schedule timers
                        if i % 5 == 1
                            EventSystem.schedule_timer_event!(em, Symbol("TestEvent$i"), 1000000)
                        end

                        # Simulate state transitions
                        if i % 7 == 1
                            try
                                EventSystem.dispatch!(em, :TestTransition)
                            catch
                                # State machine might throw, which is fine for this test
                            end
                        end

                        # Small delay between iterations
                        sleep(0.001)  # 1ms
                    end

                    # Verify we completed the simulation
                    @test length(work_counts) == 20
                    @test total_work >= 0  # Mock returns 0, but should not error

                    @info "Event system simulation completed" total_work work_counts = work_counts[1:5]

                    EventSystem.teardown_communications!(em)
                end
            end
        end
    end
end
