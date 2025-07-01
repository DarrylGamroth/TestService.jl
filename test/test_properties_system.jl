function test_properties_system()
    @testset "PropertiesSystem Module Tests" begin
        @testset "Strategy Types and Functions" begin
            @testset "OnUpdate Strategy" begin
                strategy = OnUpdate()
                @test strategy isa PublishStrategy

                # Should publish when property timestamp matches current time (updated now)
                @test PropertiesSystem.should_publish(strategy, 100, -1, 200, 200) == true   # Updated now
                @test PropertiesSystem.should_publish(strategy, 100, -1, 150, 200) == false  # Not updated now
                @test PropertiesSystem.should_publish(strategy, -1, -1, 200, 200) == true    # Never published, updated now

                # Next time should always be -1 (no scheduling)
                @test PropertiesSystem.next_time(strategy, 1000) == -1
            end

            @testset "Periodic Strategy" begin
                strategy = Periodic(1_000_000)
                @test strategy isa PublishStrategy

                # Should publish when enough time has passed since last publish
                @test PropertiesSystem.should_publish(strategy, 100, -1, 200, 1_100_200) == true   # Interval passed
                @test PropertiesSystem.should_publish(strategy, 100, -1, 200, 500_100) == false    # Interval not passed
                @test PropertiesSystem.should_publish(strategy, -1, -1, 200, 300) == true         # Never published before
                @test PropertiesSystem.should_publish(strategy, 1000, -1, 200, 1000) == false     # Already published at this time

                # Next time should be current time + period
                @test PropertiesSystem.next_time(strategy, 1000) == 1000 + 1_000_000
            end

            @testset "Scheduled Strategy" begin
                strategy = Scheduled(3000)
                @test strategy isa PublishStrategy

                # Should publish when current time matches or exceeds next scheduled time AND we haven't already published at this time
                @test PropertiesSystem.should_publish(strategy, -1, 1000, 200, 1000) == true    # Never published, reached schedule time
                @test PropertiesSystem.should_publish(strategy, -1, 1000, 200, 999) == false    # Not reached schedule time yet
                @test PropertiesSystem.should_publish(strategy, -1, 1000, 200, 1001) == true    # Past schedule time, never published
                @test PropertiesSystem.should_publish(strategy, 1000, 1000, 200, 1000) == false # Already published at this time
                @test PropertiesSystem.should_publish(strategy, 999, 1000, 200, 1001) == true   # Past schedule time, not published at this time

                # Next time should return the scheduled time
                @test PropertiesSystem.next_time(strategy, 500) == 3000  # The scheduled time
            end

            @testset "RateLimited Strategy" begin
                strategy = RateLimited(2_000_000)
                @test strategy isa PublishStrategy

                # Should publish when property is updated and enough time has passed
                @test PropertiesSystem.should_publish(strategy, 100, -1, 200, 200) == false   # Updated now but too soon
                @test PropertiesSystem.should_publish(strategy, 100, -1, 2_100_200, 2_100_200) == true  # Updated now and enough time
                @test PropertiesSystem.should_publish(strategy, 200, -1, 100, 2_100_200) == false  # Property not updated now
                @test PropertiesSystem.should_publish(strategy, -1, -1, 200, 200) == true  # Never published before, updated now

                # Next time should be current time + interval
                @test PropertiesSystem.next_time(strategy, 1000) == 1000 + 2_000_000
            end
        end

        @testset "Registry Field Updates and State Management" begin
            # Create test components
            client = Aeron.Client(Aeron.Context())
            clock = CachedEpochClock(EpochClock())
            id_generator = SnowflakeIdGenerator(1, clock)
            properties = Properties(clock)
            pm = PropertiesManager(client, properties, clock, id_generator)

            # Set up communications
            setup_communications!(pm)

            @testset "Initial Registry State After Registration" begin
                clear!(pm)
                
                # Test OnUpdate strategy registration
                register!(pm, :NodeId, 1, OnUpdate())
                @test length(pm.registry) == 1
                
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.field == :NodeId
                @test config.stream === pm.pub_data_streams[1]  # Check stream reference, not index
                @test config.last_published_ns == -1  # Never published
                @test config.next_scheduled_ns == -1  # OnUpdate doesn't use scheduling
                @test variant(config.strategy) isa PropertiesSystem.OnUpdateStrategy
                
                # Test Periodic strategy registration
                clear!(pm)
                register!(pm, :HeartbeatPeriodNs, 2, Periodic(5_000_000))
                @test length(pm.registry) == 1
                
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.field == :HeartbeatPeriodNs
                @test config.stream === pm.pub_data_streams[2]  # Check stream reference, not index
                @test config.last_published_ns == -1  # Never published
                @test config.next_scheduled_ns == 5_000_000  # Set to interval during registration
                @test variant(config.strategy) isa PropertiesSystem.PeriodicStrategy
                @test variant(config.strategy).interval_ns == 5_000_000
                
                # Test Scheduled strategy registration
                clear!(pm)
                fetch!(clock)
                current_time = time_nanos(clock)
                schedule_time = current_time + 10_000_000_000  # 10 seconds in future
                
                register!(pm, :Name, 1, Scheduled(schedule_time))
                @test length(pm.registry) == 1
                
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.field == :Name
                @test config.stream === pm.pub_data_streams[1]  # Check stream reference, not index
                @test config.last_published_ns == -1  # Never published
                @test config.next_scheduled_ns == schedule_time  # Should be set to scheduled time
                @test variant(config.strategy) isa PropertiesSystem.ScheduledStrategy
                @test variant(config.strategy).schedule_ns == schedule_time  # Correct field name
                
                # Test RateLimited strategy registration
                clear!(pm)
                register!(pm, :TestMatrix, 2, RateLimited(3_000_000))
                @test length(pm.registry) == 1
                
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.field == :TestMatrix
                @test config.stream === pm.pub_data_streams[2]  # Check stream reference, not index
                @test config.last_published_ns == -1  # Never published
                @test config.next_scheduled_ns == 3_000_000  # Set to min_interval during registration
                @test variant(config.strategy) isa PropertiesSystem.RateLimitedStrategy
                @test variant(config.strategy).min_interval_ns == 3_000_000
            end

            @testset "Registry State Updates After Publication" begin
                clear!(pm)
                
                # Test Periodic strategy state updates
                register!(pm, :HeartbeatPeriodNs, 1, Periodic(1_000_000))  # 1ms interval
                
                # Before first publication - next_scheduled_ns should be set to interval
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == -1
                @test config.next_scheduled_ns == 1_000_000  # Set to interval during registration
                
                # First publication should happen and update state
                fetch!(clock)
                current_time = time_nanos(clock)
                publications = poller(pm)
                @test publications == 1
                
                # Check state after first publication
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == current_time  # Should be updated to current time
                @test config.next_scheduled_ns == current_time + 1_000_000  # Should be current + interval
                
                # Second call shouldn't publish (too soon)
                publications = poller(pm)
                @test publications == 0
                
                # State should remain the same
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == current_time  # Unchanged
                @test config.next_scheduled_ns == current_time + 1_000_000  # Unchanged
            end

            @testset "OnUpdate Strategy State Updates" begin
                clear!(pm)
                register!(pm, :NodeId, 1, OnUpdate())
                
                # Initial state
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == -1
                @test config.next_scheduled_ns == -1
                
                # Update property and publish
                fetch!(clock)
                current_time = time_nanos(clock)
                original_value = properties[:NodeId]
                properties[:NodeId] = original_value + 1  # This gets timestamp = current_time
                
                publications = poller(pm)
                @test publications == 1
                
                # Check state after publication
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == current_time  # Should be updated
                @test config.next_scheduled_ns == -1  # OnUpdate doesn't use scheduling
                
                # Immediate second call shouldn't publish (same property timestamp)
                publications = poller(pm)
                @test publications == 0
                
                # State should remain the same
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == current_time  # Unchanged
            end

            @testset "RateLimited Strategy State Updates" begin
                clear!(pm)
                register!(pm, :NodeId, 1, RateLimited(2_000_000))  # 2ms interval
                
                # Initial state - next_scheduled_ns should be set to min_interval
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == -1
                @test config.next_scheduled_ns == 2_000_000  # Set to min_interval during registration
                
                # Update property and publish
                fetch!(clock)
                current_time = time_nanos(clock)
                original_value = properties[:NodeId]
                properties[:NodeId] = original_value + 1
                
                publications = poller(pm)
                @test publications == 1
                
                # Check state after publication
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == current_time  # Should be updated
                @test config.next_scheduled_ns == current_time + 2_000_000  # Should be current + interval
                
                # Update property again immediately - shouldn't publish (rate limited)
                properties[:NodeId] = original_value + 2
                publications = poller(pm)
                @test publications == 0
                
                # State should remain the same (no publication occurred)
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == current_time  # Unchanged
                @test config.next_scheduled_ns == current_time + 2_000_000  # Unchanged
            end

            @testset "Scheduled Strategy State Updates" begin
                clear!(pm)
                fetch!(clock)
                current_time = time_nanos(clock)
                schedule_time = current_time + 100_000_000  # 100ms in future
                
                register!(pm, :Name, 1, Scheduled(schedule_time))
                
                # Initial state
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == -1
                @test config.next_scheduled_ns == schedule_time
                
                # Before scheduled time - shouldn't publish
                publications = poller(pm)
                @test publications == 0
                
                # State should remain unchanged
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == -1  # Still never published
                @test config.next_scheduled_ns == schedule_time  # Unchanged
                
                # Advance time past schedule
                sleep(0.11)  # 110ms
                fetch!(clock)
                new_current_time = time_nanos(clock)
                
                publications = poller(pm)
                @test publications == 1
                
                # Check state after publication
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == new_current_time  # Should be updated to when published
                @test config.next_scheduled_ns == schedule_time  # Remains the original scheduled time
                
                # Immediate second call shouldn't publish
                publications = poller(pm)
                @test publications == 0
                
                # State should remain the same
                config_wrapper = pm.registry[1]
                config = variant(config_wrapper)
                @test config.last_published_ns == new_current_time  # Unchanged
            end

            @testset "Multiple Registrations State Management" begin
                clear!(pm)
                
                # Register multiple strategies
                register!(pm, :NodeId, 1, OnUpdate())
                register!(pm, :HeartbeatPeriodNs, 1, Periodic(1_000_000))
                register!(pm, :Name, 2, RateLimited(1_000_000))
                
                @test length(pm.registry) == 3
                
                # Check initial states - now next_scheduled_ns is set during registration for some strategies
                for i in 1:3
                    config_wrapper = pm.registry[i]
                    config = variant(config_wrapper)
                    @test config.last_published_ns == -1
                    if variant(config.strategy) isa PropertiesSystem.PeriodicStrategy
                        @test config.next_scheduled_ns == 1_000_000  # Set to interval during registration
                    elseif variant(config.strategy) isa PropertiesSystem.RateLimitedStrategy
                        @test config.next_scheduled_ns == 1_000_000  # Set to min_interval during registration
                    else  # OnUpdate
                        @test config.next_scheduled_ns == -1  # OnUpdate doesn't use scheduling
                    end
                end
                
                # Trigger publications and verify state updates
                fetch!(clock)
                current_time = time_nanos(clock)
                
                # Update properties to trigger OnUpdate and RateLimited
                properties[:NodeId] = properties[:NodeId] + 1
                properties[:Name] = properties[:Name] * "_test"
                
                publications = poller(pm)
                @test publications == 3  # All should publish (Periodic first time, OnUpdate+RateLimited property updated)
                
                # Verify all states were updated
                for i in 1:3
                    config_wrapper = pm.registry[i]
                    config = variant(config_wrapper)
                    @test config.last_published_ns == current_time  # All published at current time
                    
                    if variant(config.strategy) isa PropertiesSystem.PeriodicStrategy
                        expected_next = current_time + variant(config.strategy).interval_ns
                        @test config.next_scheduled_ns == expected_next
                    elseif variant(config.strategy) isa PropertiesSystem.RateLimitedStrategy
                        expected_next = current_time + variant(config.strategy).min_interval_ns
                        @test config.next_scheduled_ns == expected_next
                    else  # OnUpdate
                        @test config.next_scheduled_ns == -1
                    end
                end
            end
        end

        @testset "PropertiesManager Construction and Setup" begin
            # Create test components
            client = Aeron.Client(Aeron.Context())
            clock = CachedEpochClock(EpochClock())
            id_generator = SnowflakeIdGenerator(1, clock)
            properties = Properties(clock)

            # Create PropertiesManager
            pm = PropertiesManager(client, properties, clock, id_generator)

            @testset "Manager Construction" begin
                @test pm.client === client
                @test pm.properties === properties
                @test pm.clock === clock
                @test pm.id_generator === id_generator
                @test isempty(pm.pub_data_streams)
                @test isempty(pm.registry)
                @test length(pm.buffer) == PropertiesSystem.DEFAULT_PUBLICATION_BUFFER_SIZE
                @test pm.position_ptr[] == 0
                @test pm.communications_active == false
            end

            @testset "Convenience Accessors" begin
                @test PropertiesSystem.properties(pm) === properties
                @test is_communications_active(pm) == false
                @test pub_stream_count(pm) == 0
                @test publication_count(pm) == 0
            end

            @testset "Communication Setup/Teardown Error Handling" begin
                # setup_communications! should throw error if already active
                setup_communications!(pm)  # First setup should succeed
                @test is_communications_active(pm) == true
                
                # Second setup should throw ArgumentError
                @test_throws ArgumentError setup_communications!(pm)
                
                # teardown_communications! should succeed
                teardown_communications!(pm)  # Should succeed
                @test is_communications_active(pm) == false
                
                # Second teardown should throw ArgumentError  
                @test_throws ArgumentError teardown_communications!(pm)
                
                # Setup again should work after teardown
                setup_communications!(pm)  # Should succeed again
                @test is_communications_active(pm) == true
            end
        end

        @testset "Publication Registry Management" begin
            client = Aeron.Client(Aeron.Context())
            clock = CachedEpochClock(EpochClock())
            id_generator = SnowflakeIdGenerator(1, clock)
            properties = Properties(clock)
            pm = PropertiesManager(client, properties, clock, id_generator)

            # Set up communications which will use our mocked Aeron.add_publication
            setup_communications!(pm)

            @testset "Registration" begin
                # Test valid registrations
                strategy1 = OnUpdate()
                register!(pm, :TestMatrix, 1, strategy1)
                @test publication_count(pm) == 1

                strategy2 = Periodic(1_000_000)
                register!(pm, :TestMatrix, 2, strategy2)
                @test publication_count(pm) == 2

                # Test multiple registrations for same field
                strategy3 = RateLimited(500_000)
                register!(pm, :NodeId, 1, strategy3)
                @test publication_count(pm) == 3

                # Test invalid stream index
                @test_throws ArgumentError register!(pm, :TestMatrix, 3, strategy1)
                @test_throws ArgumentError register!(pm, :TestMatrix, 0, strategy1)
            end

            @testset "Listing" begin
                publications = list(pm)
                @test length(publications) == 3

                # Check that we can find our registrations
                fields = [pub[1] for pub in publications]
                @test :TestMatrix in fields
                @test :NodeId in fields

                indices = [pub[2] for pub in publications]
                @test 1 in indices
                @test 2 in indices
            end

            @testset "Unregistration" begin
                # Test unregister specific field-stream combination
                count = unregister!(pm, :TestMatrix, 1)  # Should succeed
                @test count > 0
                @test publication_count(pm) == 2

                # Test unregister non-existent combination - should not throw, just return 0
                count = unregister!(pm, :NonExistent, 1)
                @test count == 0
                
                # Test invalid index should still throw
                @test_throws ArgumentError unregister!(pm, :TestMatrix, 3)

                # Test unregister all for a field
                count = unregister!(pm, :TestMatrix)  # Should succeed
                @test count > 0
                @test publication_count(pm) == 1

                # Test unregister field that doesn't exist - should not throw, just return 0
                count = unregister!(pm, :NonExistent)
                @test count == 0
            end

            @testset "Clear Registry" begin
                # Add some registrations
                register!(pm, :TestMatrix, 1, OnUpdate())
                register!(pm, :NodeId, 2, Periodic(1_000_000))
                @test publication_count(pm) > 0

                # Clear all
                count = clear!(pm)
                @test count > 0
                @test publication_count(pm) == 0
                @test isempty(pm.registry)
            end
        end

        @testset "Zero Allocation Tests" begin
            client = Aeron.Client(Aeron.Context())
            clock = CachedEpochClock(EpochClock())
            id_generator = SnowflakeIdGenerator(1, clock)
            properties = Properties(clock)
            pm = PropertiesManager(client, properties, clock, id_generator)

            # Set up communications which will use our mocked Aeron.add_publication
            setup_communications!(pm)

            # Register some publications using smaller properties to avoid buffer overflow
            register!(pm, :NodeId, 1, OnUpdate())          # Int64 - small
            register!(pm, :HeartbeatPeriodNs, 1, Periodic(1_000_000))  # Int64 - small
            register!(pm, :Name, 2, RateLimited(500_000))   # String - reasonably small

            @testset "Poller Zero Allocations" begin
                # Warm up the functions first
                for _ in 1:10
                    poller(pm)
                end

                # Force compilation of all paths
                GC.gc()  # Clean up any compilation artifacts

                # Test that poller doesn't allocate
                allocs = @allocated poller(pm)
                @test allocs == 0

                # Test multiple calls to ensure consistency
                for _ in 1:5
                    allocs = @allocated poller(pm)
                    @test allocs == 0
                end
            end

            @testset "Strategy Function Zero Allocations" begin
                strategies = [
                    OnUpdate(),
                    Periodic(1_000_000),
                    Scheduled(3000),
                    RateLimited(500_000)
                ]

                for strategy in strategies
                    # Warm up PropertiesSystem.should_publish
                    for _ in 1:10
                        PropertiesSystem.should_publish(strategy, 100, 1000, 200, 1500)
                    end

                    # Warm up PropertiesSystem.next_time
                    for _ in 1:10
                        PropertiesSystem.next_time(strategy, 1000)
                    end

                    GC.gc()

                    # Test PropertiesSystem.should_publish doesn't allocate
                    allocs = @allocated PropertiesSystem.should_publish(strategy, 100, 1000, 200, 1500)
                    @test allocs == 0

                    # Test PropertiesSystem.next_time doesn't allocate
                    allocs = @allocated PropertiesSystem.next_time(strategy, 1000)
                    @test allocs == 0
                end
            end

            @testset "Registry Access Zero Allocations" begin
                # Warm up registry iteration
                for _ in 1:10
                    for config_wrapper in pm.registry
                        config = variant(config_wrapper)
                        config.field
                    end
                end

                GC.gc()

                # Test that iterating through registry doesn't allocate
                allocs = @allocated begin
                    for config_wrapper in pm.registry
                        config = variant(config_wrapper)
                        config.field
                    end
                end
                @test allocs == 0

                # Test accessing registry elements doesn't allocate
                if !isempty(pm.registry)
                    # Warm up
                    for _ in 1:10
                        config_wrapper = pm.registry[1]
                        variant(config_wrapper)
                    end

                    GC.gc()

                    allocs = @allocated begin
                        config_wrapper = pm.registry[1]
                        variant(config_wrapper)
                    end
                    @test allocs == 0
                end
            end
        end

        @testset "Type Stability Tests" begin
            client = Aeron.Client(Aeron.Context())
            clock = CachedEpochClock(EpochClock())
            id_generator = SnowflakeIdGenerator(1, clock)
            properties = Properties(clock)
            pm = PropertiesManager(client, properties, clock, id_generator)

            # Set up communications which will use our mocked Aeron.add_publication
            setup_communications!(pm)

            # Register publications with different strategies using smaller properties
            register!(pm, :NodeId, 1, OnUpdate())
            register!(pm, :HeartbeatPeriodNs, 1, Periodic(1_000_000))
            register!(pm, :Name, 2, RateLimited(500_000))

            @testset "Registry Type Stability" begin
                @test pm.registry isa Vector{PropertiesSystem.PropertyConfigType}

                # Ensure all configs are of the expected sum type
                for config_wrapper in pm.registry
                    @test config_wrapper isa PropertiesSystem.PropertyConfigType
                    config = variant(config_wrapper)
                    @test config isa PropertiesSystem.PropertyConfig
                end
            end

            @testset "Strategy Type Stability" begin
                strategies = [OnUpdate(), Periodic(1_000_000), RateLimited(500_000)]

                for strategy in strategies
                    @test strategy isa PublishStrategy

                    # Test that function calls are type stable
                    result = PropertiesSystem.should_publish(strategy, 100, 1000, 200, 1500)
                    @test result isa Bool

                    next = PropertiesSystem.next_time(strategy, 1000)
                    @test next isa Int64
                end
            end
        end

        @testset "Strategy Integration Tests - Real Poller Usage" begin
            client = Aeron.Client(Aeron.Context())
            clock = CachedEpochClock(EpochClock())
            id_generator = SnowflakeIdGenerator(1, clock)
            properties = Properties(clock)
            pm = PropertiesManager(client, properties, clock, id_generator)

            # Set up communications
            setup_communications!(pm)

            @testset "OnUpdate Strategy Integration" begin
                # Clear any existing registrations and ensure clean state
                clear!(pm)
                
                # Force the clock to advance so properties won't have timestamp = current time
                sleep(0.001)
                fetch!(clock)  # Advance clock from initial 0 time
                
                # Register property with OnUpdate strategy
                register!(pm, :NodeId, 1, OnUpdate())
                
                # Initial state - property timestamp should be old (0) vs current clock time
                initial_publications = poller(pm)
                @test initial_publications == 0

                # Simulate agent loop: fetch clock, then update property within same time
                fetch!(clock)  # This sets the current time
                original_value = properties[:NodeId]
                properties[:NodeId] = original_value + 1  # Property gets timestamp = current time
                
                # Now poller should publish once (property timestamp matches current clock time)
                publications = poller(pm)
                @test publications == 1

                # Subsequent calls in same loop iteration should not publish again
                publications = poller(pm)
                @test publications == 0

                # Next loop iteration: advance clock, then update property
                fetch!(clock)  # Advance to next time
                properties[:NodeId] = original_value + 2  # Property gets new timestamp
                publications = poller(pm)
                @test publications == 1
            end

            @testset "Periodic Strategy Integration" begin
                clear!(pm)
                
                # Register property with Periodic strategy (1ms interval for fast testing)
                register!(pm, :HeartbeatPeriodNs, 1, Periodic(1_000_000))  # 1ms
                
                # First publication should happen immediately
                publications = poller(pm)
                @test publications == 1

                # Subsequent calls within the interval should not publish
                publications = poller(pm)
                @test publications == 0

                # Sleep a bit and update clock to pass the interval
                sleep(0.002)  # 2ms to ensure we pass the 1ms interval
                fetch!(clock)
                
                # Now should publish again
                publications = poller(pm)
                @test publications == 1

                # Test multiple intervals
                sleep(0.003)  # 3ms
                fetch!(clock)
                publications = poller(pm)
                @test publications == 1
            end

            @testset "RateLimited Strategy Integration" begin
                clear!(pm)
                
                # Register property with RateLimited strategy (1ms minimum interval)
                register!(pm, :NodeId, 1, RateLimited(1_000_000))  # 1ms min interval
                
                # Simulate agent loop: fetch clock, then update property
                fetch!(clock)
                original_value = properties[:NodeId]
                properties[:NodeId] = original_value + 10  # Property gets current timestamp
                publications = poller(pm)
                @test publications == 1  # First publication should work

                # Update property again in same loop - should not publish (rate limited)
                properties[:NodeId] = original_value + 11
                publications = poller(pm)
                @test publications == 0

                # Wait for rate limit to pass, then simulate next agent loop
                sleep(0.002)  # 2ms
                fetch!(clock)  # Advance clock (like next agent loop iteration)
                properties[:NodeId] = original_value + 12  # Update with new timestamp
                publications = poller(pm)
                @test publications == 1
            end

            @testset "Scheduled Strategy Integration" begin
                clear!(pm)
                
                # Get current time and schedule for 1 second in the future
                fetch!(clock)  # Get current cached time
                current_time = time_nanos(clock)
                schedule_time = current_time + 1_000_000_000  # 1 second in the future
                
                register!(pm, :Name, 1, Scheduled(schedule_time))
                
                # Should not publish before scheduled time
                publications = poller(pm)
                @test publications == 0

                # Sleep past the scheduled time and advance clock
                sleep(1.1)  # 1.1 seconds to ensure we pass the 1 second schedule
                fetch!(clock)
                
                # Should publish now
                publications = poller(pm)
                @test publications == 1

                # Should not publish again
                publications = poller(pm)
                @test publications == 0
            end

            @testset "Multiple Strategy Integration" begin
                clear!(pm)
                
                # Force clock to advance from 0 to avoid timestamp=0 issues
                sleep(0.001)
                fetch!(clock)
                
                # Register multiple properties with different strategies
                register!(pm, :NodeId, 1, OnUpdate())
                register!(pm, :HeartbeatPeriodNs, 1, Periodic(1_000_000))  # 1ms
                register!(pm, :Name, 2, RateLimited(1_000_000))  # 1ms min interval
                
                # First check - only Periodic should publish (first time, never published before)
                # OnUpdate won't publish (property not recently updated)
                # RateLimited won't publish (property not recently updated)
                publications = poller(pm)
                @test publications == 1  # Only Periodic publishes first time

                # Now simulate agent loop with property updates
                fetch!(clock)  # Next agent loop iteration
                
                # Update properties (they'll get current timestamp)
                original_node_id = properties[:NodeId]
                properties[:NodeId] = original_node_id + 100
                
                original_name = properties[:Name]
                properties[:Name] = original_name * "_updated"
                
                # Should publish OnUpdate (property changed) and RateLimited (property changed)
                # Periodic shouldn't publish yet (interval not passed)
                publications = poller(pm)
                @test publications == 2

                # Immediate second call - nothing should publish
                publications = poller(pm)
                @test publications == 0

                # Wait for intervals to pass, then simulate next agent loop
                sleep(0.002)  # 2ms
                fetch!(clock)  # Next agent loop
                
                # Only Periodic should publish now (others need property updates)
                publications = poller(pm)
                @test publications == 1
            end

            @testset "Agent-like Work Loop Simulation" begin
                clear!(pm)
                
                # Set up multiple registrations like a real agent might
                register!(pm, :NodeId, 1, OnUpdate())
                register!(pm, :HeartbeatPeriodNs, 1, Periodic(5_000_000))  # 5ms
                register!(pm, :Name, 2, RateLimited(2_000_000))  # 2ms min interval
                
                work_counts = Int[]
                total_publications = 0
                
                # Simulate agent work loop for 50 iterations
                for i in 1:50
                    # Update clock first (like agent does)
                    fetch!(clock)
                    
                    # Occasionally update properties (simulate real changes)
                    # Properties get timestamp = current clock time
                    if i % 10 == 1
                        properties[:NodeId] = properties[:NodeId] + 1
                    end
                    if i % 15 == 1
                        properties[:Name] = properties[:Name] * "_$i"
                    end
                    
                    # Call poller (like agent does)
                    work_count = poller(pm)
                    push!(work_counts, work_count)
                    total_publications += work_count
                    
                    # Small delay between iterations
                    sleep(0.001)  # 1ms
                end
                
                # Verify we got some publications
                @test total_publications > 0
                @test length(work_counts) == 50
                
                # Verify OnUpdate strategy worked (should publish when NodeId changed)
                node_id_updates = count(i -> i % 10 == 1, 1:50)  # Times we updated NodeId
                @test sum(work_counts[1:10:50]) >= node_id_updates  # At least one pub per update
                
                # Verify Periodic strategy worked (should publish every ~5ms)
                # With 50ms total and 5ms interval, expect around 10 publications
                periodic_pubs = count(work_counts .> 0)
                @test periodic_pubs >= 8  # Allow some variance due to timing
                
                @info "Agent simulation completed" total_publications work_counts=work_counts[1:10]
            end
        end
    end
end
