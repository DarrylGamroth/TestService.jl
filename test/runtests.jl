using Test
using Aeron  # This will now use our mock Aeron from test Project.toml
using Clocks
using SnowflakeId
using Logging
using LightSumTypes
using StaticKV

# Set up test environment variables BEFORE loading PropertiesSystem
# This is needed because the @generate_pub_data_uri_fields macro runs at compilation time
ENV["BLOCK_NAME"] = "TestBlock"
ENV["BLOCK_ID"] = "12345"
ENV["STATUS_URI"] = "aeron:ipc"
ENV["STATUS_STREAM_ID"] = "1001"
ENV["CONTROL_URI"] = "aeron:ipc"
ENV["CONTROL_STREAM_ID"] = "1002"
ENV["HEARTBEAT_PERIOD_NS"] = "5000000000"
ENV["LOG_LEVEL"] = "Info"
ENV["GC_LOGGING"] = "false"
# Set up pub data URIs for testing
ENV["PUB_DATA_URI_1"] = "aeron:ipc"
ENV["PUB_DATA_STREAM_1"] = "2001"
ENV["PUB_DATA_URI_2"] = "aeron:ipc"
ENV["PUB_DATA_STREAM_2"] = "2002"

# Include the modules in the correct dependency order
include("../src/messaging/MessagingSystem.jl")
include("../src/timer/TimerSystem.jl")
include("../src/properties/PropertiesSystem.jl")
include("../src/events/EventSystem.jl")
using .MessagingSystem
using .TimerSystem
using .PropertiesSystem
using .EventSystem

# Include all test modules
include("test_strategies.jl")
include("test_properties_system.jl")
include("test_event_system.jl")

# Run all tests
@testset "TestService.jl Tests" begin
    @testset "LightSumTypes Strategies Tests" begin
        test_lightsumtypes_strategies()
    end
    
    @testset "PropertiesSystem Tests" begin
        test_properties_system()
    end
    
    @testset "EventSystem Tests" begin
        test_event_system()
    end
end
