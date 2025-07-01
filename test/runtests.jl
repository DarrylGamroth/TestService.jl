using Test
using Aeron
using Clocks
using SnowflakeId
using Logging
using LightSumTypes

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

# Include the PropertiesSystem module directly
include("../src/properties/PropertiesSystem.jl")
using .PropertiesSystem

# Mock Aeron.Publication for testing
struct MockPublication
    uri::String
    stream_id::Int32
    is_connected::Bool

    MockPublication(uri, stream_id) = new(uri, stream_id, true)
end

# Mock Aeron functions for testing
function Aeron.add_publication(client::Aeron.Client, uri::String, stream_id::Int32)
    return MockPublication(uri, stream_id)
end

function Aeron.is_connected(pub::MockPublication)
    return pub.is_connected
end

# Mock the Aeron.Publication methods that might be called
function Aeron.is_connected(pub::Aeron.Publication)
    return true  # Always connected for testing
end

# Create a real buffer for the mock
const BUFFER::Vector{UInt8} = Vector{UInt8}(undef, 2048)

function Aeron.try_claim(pub::Aeron.Publication, length::Int)
    # Create a mock struct that BufferClaim expects with real buffer pointer
    mock_struct = Aeron.LibAeron.aeron_buffer_claim_stct(C_NULL, pointer(BUFFER), length)
    # Return a mock claim and positive result
    return (Aeron.BufferClaim(mock_struct), length)
end

function Aeron.offer(pub::MockPublication, buffer::Vector{UInt8})
    return length(buffer)  # Return the length to simulate successful offer
end

function Aeron.offer(pub::MockPublication, buffer)
    return 100  # Return positive value to simulate successful offer
end

function Aeron.offer(pub::Aeron.Publication, buffer::Vector{UInt8})
    return length(buffer)  # Return the length to simulate successful offer
end

function Aeron.offer(pub::Aeron.Publication, buffer)
    return 100  # Return positive value to simulate successful offer
end

function Aeron.try_claim(pub::MockPublication, length::Int)
    # Create a mock struct that BufferClaim expects with real buffer pointer
    mock_struct = Aeron.LibAeron.aeron_buffer_claim_stct(C_NULL, pointer(BUFFER), length)
    # Return a mock claim and positive result
    return (Aeron.BufferClaim(mock_struct), length)
end

# Mock close function
function Base.close(pub::MockPublication)
    # Nothing to do for mock
end

# Include all test modules
include("test_strategies.jl")
include("test_properties_system.jl")

# Run all tests
@testset "TestService.jl Tests" begin
    @testset "LightSumTypes Strategies Tests" begin
        test_lightsumtypes_strategies()
    end
    
    @testset "PropertiesSystem Tests" begin
        test_properties_system()
    end
end
