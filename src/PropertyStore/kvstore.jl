@kvstore Properties begin
    Name::String => (
        get(ENV, "BLOCK_NAME") do
            throw(EnvironmentVariableError("BLOCK_NAME"))
        end;
        access = AccessMode.READABLE
    )
    NodeId::Int64 => (
        parse(Int64, get(ENV, "BLOCK_ID") do
            throw(EnvironmentVariableError("BLOCK_ID"))
        end);
        access = AccessMode.READABLE
    )
    StatusURI::String => (
        get(ENV, "STATUS_URI") do
            throw(EnvironmentVariableError("STATUS_URI"))
        end;
        access = AccessMode.READABLE
    )
    StatusStreamID::Int64 => (
        parse(Int64, get(ENV, "STATUS_STREAM_ID") do
            throw(EnvironmentVariableError("STATUS_STREAM_ID"))
        end);
        access = AccessMode.READABLE
    )
    ControlURI::String => (
        get(ENV, "CONTROL_URI") do
            throw(EnvironmentVariableError("CONTROL_URI"))
        end;
        access = AccessMode.READABLE
    )
    ControlStreamID::Int64 => (
        parse(Int64, get(ENV, "CONTROL_STREAM_ID") do
            throw(EnvironmentVariableError("CONTROL_STREAM_ID"))
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
    LateMessageThresholdNs::Int64 => (
        parse(Int64, get(ENV, "LATE_MESSAGE_THRESHOLD_NS", "1000000000"));
        access = AccessMode.READABLE
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
    GCBytes::Int64 => (
        0;
        access=AccessMode.READABLE,
        on_get=(obj, name, val) -> Base.gc_bytes()
    )
    GCEnable::Bool => (
        true;
        on_set=(obj, name, val) -> GC.enable(val),
    )
    GCLogging::Bool => (
        parse(Bool, get(ENV, "GC_LOGGING", "false"));
        on_set=(obj, name, val) -> (GC.enable_logging(val); val),
        on_get=(obj, name, val) -> GC.logging_enabled()
    )
    TestMatrix::Array{Float32,3} => (
        rand(Float32, 10, 5, 2)
    )

    @generate_sub_data_uri_keys
    @generate_pub_data_uri_keys
end