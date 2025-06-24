# Helper macro to generate fields from SUB_DATA_URI_* environment variables
macro generate_data_uri_fields()
    fields = Expr(:block)

    # Scan environment at macro expansion time
    for (key, value) in ENV
        if startswith(key, "SUB_DATA_URI_")
            # Extract index number
            idx = parse(Int, replace(key, "SUB_DATA_URI_" => ""))
            uri_field = Symbol("DataURI$(idx)")
            stream_field = Symbol("DataStreamID$(idx)")

            # Add URI field
            push!(fields.args, :(
                $uri_field::String => (value => $(value))
            ))

            # Add corresponding stream ID field
            stream_key = "SUB_DATA_STREAM_$(idx)"
            if haskey(ENV, stream_key)
                stream_value = parse(Int, ENV[stream_key])
                push!(fields.args, :(
                    $stream_field::Int64 => (value => $stream_value)
                ))
            end
        end
    end

    return fields
end

@properties Properties begin
    Name::String => (value => get(ENV, "BLOCK_NAME") do
        error("Environment variable BLOCK_NAME not found")
    end)
    NodeId::Int64 => (value => parse(Int64, get(ENV, "BLOCK_ID") do
        error("Environment variable BLOCK_ID not found")
    end))
    HeartbeatPeriodNs::Int64 => (value => parse(Int64, get(ENV, "HEARTBEAT_PERIOD_NS", "10000000000")))
    StatusURI::String => (value => get(ENV, "STATUS_URI") do
        error("Environment variable STATUS_URI not found")
    end)
    StatusStreamID::Int64 => (value => parse(Int64, get(ENV, "STATUS_STREAM_ID") do
        error("Environment variable STATUS_STREAM_ID not found")
    end))
    ControlURI::String => (value => get(ENV, "CONTROL_URI") do
        error("Environment variable CONTROL_URI not found")
    end)
    ControlStreamID::Int64 => (value => parse(Int64, get(ENV, "CONTROL_STREAM_ID") do
        error("Environment variable CONTROL_STREAM_ID not found")
    end))
    ControlStreamFilter::String => (value => get(ENV, "CONTROL_STREAM_FILTER", nothing))
    DataConnectionCount::Int64 => (
        value => count(startswith("SUB_DATA_URI_"), keys(ENV)),
        access => AccessMode.READABLE
    )
    TestMatrix::Matrix{Float32} => (
        value => rand(Float32, 10, 10)
    )
        
    @generate_data_uri_fields
end

