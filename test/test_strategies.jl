"""
Test suite for strategy system.
Tests the core logic for when and how properties should be published.
"""
function test_strategies()
    @testset "Strategy Creation and Types" begin
        @test OnUpdate() isa PublishStrategy
        @test Periodic(1000) isa PublishStrategy  
        @test RateLimited(500) isa PublishStrategy
        @test Scheduled(2000) isa PublishStrategy
        
        # Test that all strategies have consistent type
        s1, s2, s3, s4 = OnUpdate(), Periodic(1000), RateLimited(500), Scheduled(2000)
        @test typeof(s1) == typeof(s2) == typeof(s3) == typeof(s4) == PublishStrategy
    end
    
    @testset "OnUpdate Strategy Logic" begin
        strategy = OnUpdate()
        
        # Should publish when property was updated in current loop (timestamp matches current time)
        @test should_publish(strategy, 100, -1, 200, 200) == true   # Property updated now
        @test should_publish(strategy, 100, -1, 150, 200) == false  # Property not updated now
        @test should_publish(strategy, -1, -1, 200, 200) == true    # Never published, property updated
        @test should_publish(strategy, 200, -1, 200, 200) == false  # Already published this update
        
        # Next time should always be -1 (no scheduling)
        @test next_time(strategy, 1000) == -1
    end
    
    @testset "Periodic Strategy Logic" begin
        strategy = Periodic(1000)  # 1000ns interval
        
        # First publication should always happen
        @test should_publish(strategy, -1, -1, 100, 200) == true
        
        # Should publish when interval has elapsed
        @test should_publish(strategy, 100, -1, 150, 1200) == true   # 1200 - 100 >= 1000
        @test should_publish(strategy, 100, -1, 150, 800) == false   # 800 - 100 < 1000
        @test should_publish(strategy, 200, -1, 150, 200) == false   # Already published at this time
        
        # Next time calculation
        @test next_time(strategy, 1000) == 2000  # 1000 + 1000
    end
    
    @testset "RateLimited Strategy Logic" begin
        strategy = RateLimited(500)  # 500ns minimum interval
        
        # Should not publish if property wasn't updated in current loop
        @test should_publish(strategy, 100, -1, 150, 200) == false  # Property not updated now
        
        # Should publish if property was updated and enough time elapsed
        @test should_publish(strategy, 100, -1, 200, 200) == false  # Updated now but too soon
        @test should_publish(strategy, 100, -1, 700, 700) == true   # Updated now and enough time
        @test should_publish(strategy, -1, -1, 200, 200) == true    # Never published, updated now
        
        # Next time calculation  
        @test next_time(strategy, 1000) == 1500  # 1000 + 500
    end
    
    @testset "Scheduled Strategy Logic" begin
        strategy = Scheduled(1500)  # Scheduled for time 1500
        
        # Should publish when current time >= scheduled time and not already published at this time
        @test should_publish(strategy, -1, 1500, 200, 1600) == true   # Past schedule time, never published
        @test should_publish(strategy, -1, 1500, 200, 1400) == false  # Not reached schedule time yet
        @test should_publish(strategy, -1, 1500, 200, 1500) == true   # Exactly at schedule time
        @test should_publish(strategy, 1500, 1500, 200, 1500) == false # Already published at this time
        @test should_publish(strategy, 1400, 1500, 200, 1600) == true  # Past schedule, not yet published at current time
        
        # Next time should return the scheduled time
        @test next_time(strategy, 1000) == 1500
    end
    
    @testset "Strategy Array Operations" begin
        strategies = [OnUpdate(), Periodic(1000), RateLimited(500), Scheduled(2000)]
        
        @test length(strategies) == 4
        @test eltype(strategies) == PublishStrategy
        
        # Test that we can call functions on all strategies
        for strategy in strategies
            @test should_publish(strategy, 100, -1, 200, 1500) isa Bool
            @test next_time(strategy, 1000) isa Int64
        end
    end
    
    @testset "Zero Allocation Tests" begin
        # Create strategies
        s1, s2, s3, s4 = OnUpdate(), Periodic(1000), RateLimited(500), Scheduled(2000)
        strategies = [s1, s2, s3, s4]
        
        # Warm up
        for _ in 1:100
            for strategy in strategies
                should_publish(strategy, 100, -1, 200, 1500)
                next_time(strategy, 1000)
            end
        end
        
        GC.gc()
        GC.gc()
        
        # Test should_publish allocations
        allocs = @allocated begin
            for strategy in strategies
                should_publish(strategy, 100, -1, 200, 1500)
            end
        end
        @test allocs == 0
        
        # Test next_time allocations  
        allocs = @allocated begin
            for strategy in strategies
                next_time(strategy, 1000)
            end
        end
        @test allocs == 0
        
        # Test individual strategy calls
        @test (@allocated should_publish(s1, 100, -1, 200, 1500)) == 0
        @test (@allocated next_time(s2, 1000)) == 0
    end
    
    @testset "Type Stability" begin
        s1 = OnUpdate()
        s2 = Periodic(1000)
        s3 = RateLimited(500)
        s4 = Scheduled(2000)
        
        # Test that functions are type-stable
        @test (@inferred should_publish(s1, 100, -1, 200, 1500)) isa Bool
        @test (@inferred should_publish(s2, 100, -1, 200, 1500)) isa Bool
        @test (@inferred should_publish(s3, 100, -1, 200, 1500)) isa Bool
        @test (@inferred should_publish(s4, 100, -1, 200, 1500)) isa Bool
        
        @test (@inferred next_time(s1, 1000)) isa Int64
        @test (@inferred next_time(s2, 1000)) isa Int64
        @test (@inferred next_time(s3, 1000)) isa Int64
        @test (@inferred next_time(s4, 1000)) isa Int64
    end
end
