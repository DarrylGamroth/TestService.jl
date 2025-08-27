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
    LogLevel::Symbol => (
        Symbol(get(ENV, "LOG_LEVEL", "Debug"));
        on_set = (obj, name, val) -> begin
            if !isdefined(Logging, val)
                throw(PropertyTypeError(name, Symbol, typeof(val)))
            end

            level = getfield(Logging, val)
            Logging.disable_logging(level)

            return val
        end
    )
    GCLogging::Bool => (
        parse(Bool, get(ENV, "GC_LOGGING", "false"));
        on_set = (obj, name, val) -> begin
            GC.enable_logging(val)
            return val
        end
    )
    TestMatrix::Array{Float32,3} => (
        rand(Float32, 10, 5, 2);
    )

    @generate_sub_data_uri_keys
    @generate_pub_data_uri_keys
end