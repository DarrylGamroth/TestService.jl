@properties Properties begin
    Name::String => (
        value => get(ENV, "BLOCK_NAME") do
            error("Environment variable BLOCK_NAME not found")
        end,
        access => AccessMode.READABLE
    )
    NodeId::Int64 => (
        value => parse(Int64, get(ENV, "BLOCK_ID") do
            error("Environment variable BLOCK_ID not found")
        end),
        access => AccessMode.READABLE
    )
    StatusURI::String => (
        value => get(ENV, "STATUS_URI") do
            error("Environment variable STATUS_URI not found")
        end,
        access => AccessMode.READABLE
    )
    StatusStreamID::Int64 => (
        value => parse(Int64, get(ENV, "STATUS_STREAM_ID") do
            error("Environment variable STATUS_STREAM_ID not found")
        end),
        access => AccessMode.READABLE
    )
    ControlURI::String => (
        value => get(ENV, "CONTROL_URI") do
            error("Environment variable CONTROL_URI not found")
        end,
        access => AccessMode.READABLE
    )
    ControlStreamID::Int64 => (
        value => parse(Int64, get(ENV, "CONTROL_STREAM_ID") do
            error("Environment variable CONTROL_STREAM_ID not found")
        end),
        access => AccessMode.READABLE
    )
    ControlStreamFilter::String => (
        value => get(ENV, "CONTROL_STREAM_FILTER", nothing),
        access => AccessMode.READABLE
    )
    HeartbeatPeriodNs::Int64 => (
        value => parse(Int64, get(ENV, "HEARTBEAT_PERIOD_NS", "10000000000")),
    )
    LogLevel::Symbol => (
        value => Symbol(get(ENV, "LOG_LEVEL", "Info")),
        on_set => (obj, name, val) -> begin
            if !isdefined(Logging, val)
                throw(ArgumentError("Invalid log level: $val"))
            end

            level = getfield(Logging, val)
            Logging.disable_logging(level)

            return val
        end
    )
    GCLogging::Bool => (
        value => begin
            v = lowercase(get(ENV, "GC_LOGGING", "false"))
            v == "true" ? true : v == "false" ? false : throw(ArgumentError("Invalid value for GC_LOGGING: $v"))
        end,
        on_set => (obj, name, val) -> begin
            GC.enable_logging(val)
            return val
        end
    )
    TestMatrix::Array{Float32,3} => (
        value => rand(Float32, 10, 5, 2)
    )

    @generate_sub_data_uri_fields
    @generate_pub_data_uri_fields
end