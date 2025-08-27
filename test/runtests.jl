using Test
using TestService
using Aeron
using Agent
using Clocks
using SnowflakeId
using StaticKV
using LightSumTypes

# Set up test environment variables before loading TestService
ENV["BLOCK_NAME"] = "TestAgent"
ENV["BLOCK_ID"] = "1"
ENV["STATUS_URI"] = "aeron:ipc"
ENV["STATUS_STREAM_ID"] = "1001"
ENV["CONTROL_URI"] = "aeron:ipc"
ENV["CONTROL_STREAM_ID"] = "1002"
ENV["HEARTBEAT_PERIOD_NS"] = "5000000000"
ENV["LOG_LEVEL"] = "Error"  # Reduce log noise during tests
ENV["GC_LOGGING"] = "false"

# Set up minimal pub/sub data connections for testing
ENV["PUB_DATA_URI_1"] = "aeron:ipc"
ENV["PUB_DATA_STREAM_1"] = "2001"
ENV["PUB_DATA_URI_2"] = "aeron:ipc"
ENV["PUB_DATA_STREAM_2"] = "2002"
ENV["SUB_DATA_URI_1"] = "aeron:ipc"
ENV["SUB_DATA_STREAM_1"] = "3001"
ENV["SUB_DATA_URI_2"] = "aeron:ipc"
ENV["SUB_DATA_STREAM_2"] = "3002"

# Include individual test modules
include("test_strategies.jl")
include("test_rtcagent.jl")
include("test_property_publishing.jl")
include("test_communications.jl")
include("test_property_store.jl")
include("test_timers.jl")
include("test_utilities.jl")
include("test_exceptions.jl")
include("test_integration.jl")

# Run all test suites
@testset "TestService.jl Complete Test Suite" begin
    test_strategies()
    test_rtcagent()
    test_property_publishing()
    test_communications()
    test_property_store()
    test_timers()
    test_utilities()
    test_exceptions()
    test_integration()
end

@testset "TestService.jl Tests" begin
    @testset "Strategy System Tests" begin
        test_strategies()
    end
    
    @testset "RtcAgent Core Tests" begin
        test_rtcagent()
    end
    
    @testset "Property Publishing Tests" begin
        test_property_publishing()
    end
    
    @testset "Communications Tests" begin
        test_communications()
    end
    
    @testset "PropertyStore Tests" begin
        test_property_store()
    end
    
    @testset "Timer System Tests" begin
        test_timers()
    end
    
    @testset "Utilities Tests" begin
        test_utilities()
    end
    
    @testset "Exception Handling Tests" begin
        test_exceptions()
    end
    
    @testset "Integration Tests" begin
        test_integration()
    end
end
