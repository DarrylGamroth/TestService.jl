@kvstore Properties begin
    Name::String => (
        get(ENV, "BLOCK_NAME") do
            error("Environment variable BLOCK_NAME not found")
        end;
        access = AccessMode.READABLE
    )
    NodeId::Int64 => (
        parse(Int64, get(ENV, "BLOCK_ID") do
            error("Environment variable BLOCK_ID not found")
        end);
        access = AccessMode.READABLE
    )
    StatusURI::String => (
        get(ENV, "STATUS_URI") do
            error("Environment variable STATUS_URI not found")
        end;
        access = AccessMode.READABLE
    )
    StatusStreamID::Int64 => (
        parse(Int64, get(ENV, "STATUS_STREAM_ID") do
            error("Environment variable STATUS_STREAM_ID not found")
        end);
        access = AccessMode.READABLE
    )
    ControlURI::String => (
        get(ENV, "CONTROL_URI") do
            error("Environment variable CONTROL_URI not found")
        end;
        access = AccessMode.READABLE
    )
    ControlStreamID::Int64 => (
        parse(Int64, get(ENV, "CONTROL_STREAM_ID") do
            error("Environment variable CONTROL_STREAM_ID not found")
        end);
        access = AccessMode.READABLE
    )
    ControlFilter::String => (
        get(ENV, "CONTROL_FILTER", nothing);
        access = AccessMode.READABLE
    )
    HeartbeatPeriodNs::Int64 => (
        parse(Int64, get(ENV, "HEARTBEAT_PERIOD_NS", "10000000000"))
    )
    LogLevel::Symbol => (
        Symbol(get(ENV, "LOG_LEVEL", "Debug"));
        on_set = (obj, name, val) -> begin
            if !isdefined(Logging, val)
                throw(ArgumentError("Invalid log level: $val"))
            end

            level = getfield(Logging, val)
            Logging.disable_logging(level)

            return val
        end
    )
    GCLogging::Bool => (
        begin
            v = lowercase(get(ENV, "GC_LOGGING", "false"))
            v == "true" ? true : v == "false" ? false : throw(ArgumentError("Invalid value for GC_LOGGING: $v"))
        end;
        on_set = (obj, name, val) -> begin
            GC.enable_logging(val)
            return val
        end
    )
    TestMatrix::Array{Float32,3} => (
        rand(Float32, 10, 5, 2);
        access = AccessMode.READABLE | AccessMode.MUTABLE
    )

    @generate_sub_data_uri_keys
    @generate_pub_data_uri_keys
end