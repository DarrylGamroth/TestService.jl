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
include("test_adapters.jl")
include("test_property_publishing.jl")
include("test_communications.jl")
include("test_property_store.jl")
include("test_timers.jl")
include("test_exceptions.jl")
include("test_integration.jl")

# Run all test suites with organized structure
@testset "TestService.jl Tests" begin
    # Tests that don't need Aeron context
    @testset "Strategy System Tests" begin
        test_strategies()
    end

    @testset "PropertyStore Tests" begin
        test_property_store()
    end

    # Tests that need shared Aeron context
    MediaDriver.launch_embedded() do driver
        Aeron.Context() do context
            Aeron.aeron_dir!(context, MediaDriver.aeron_dir(driver))
            Aeron.Client(context) do client
                @testset "RtcAgent Core Tests" begin
                    test_rtcagent(client)
                end

                @testset "Stream Adapter Tests" begin
                    test_adapters(client)
                end

                @testset "Property Publishing Tests" begin
                    test_property_publishing(client)
                end

                @testset "Communications Tests" begin
                    test_communications(client)
                end

                @testset "Timer System Tests" begin
                    test_timers(client)
                end

                @testset "Exception Handling Tests" begin
                    test_exceptions(client)
                end

                @testset "Integration Tests" begin
                    test_integration(client)
                end
            end
        end
    end
end
