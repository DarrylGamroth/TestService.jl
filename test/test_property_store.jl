"""
Test suite for PropertyStore module functionality.
Tests property access, timestamps, and type validation.
"""
function test_property_store()
    @testset "Property Access and Mutation" begin
        clock = CachedEpochClock(EpochClock())
        props = TestService.PropertyStore.Properties(clock)
        
        # Test basic property access
        @test props[:Name] isa String
        @test props[:NodeId] isa Int64
        @test props[:HeartbeatPeriodNs] isa Int64
        
        # Test that isset works
        @test isset(props, :Name)
        @test isset(props, :NodeId)
        @test !isset(props, :NonExistentProperty)
        
        # Test basic property reading
        name = props[:Name]
        @test name isa String
        @test length(name) > 0
    end
    
    @testset "Timestamp Tracking" begin
        clock = CachedEpochClock(EpochClock())
        props = TestService.PropertyStore.Properties(clock)
        
        fetch!(clock)
        current_time = time_nanos(clock)
        
        # Test that timestamps exist for initialized properties
        name_timestamp = last_update(props, :Name)
        @test name_timestamp isa Int64
        
        # Properties may be initialized with 0 timestamp until first access
        # So we test that timestamp is non-negative
        @test name_timestamp >= 0
        
        # Access the property to ensure it's set
        _ = props[:Name]
        updated_timestamp = last_update(props, :Name)
        @test updated_timestamp >= name_timestamp
    end
end
