# Helper macro to generate fields from SUB_DATA_URI_* environment variables
macro generate_sub_data_uri_fields()
    fields = []
    connection_count = 0

    # Scan environment at macro expansion time
    for (key, value) in ENV
        if startswith(key, "SUB_DATA_URI_")
            connection_count += 1
            # Extract index number
            idx = parse(Int, replace(key, "SUB_DATA_URI_" => ""))
            uri_field = Symbol("SubDataURI$(idx)")
            stream_field = Symbol("SubDataStreamID$(idx)")

            # Add URI field (read-only)
            push!(fields, :(
                $uri_field::String => (
                    value => $value,
                    access => AccessMode.READABLE
                )
            ))

            # Add corresponding stream ID field (read-only)
            stream_key = "SUB_DATA_STREAM_$(idx)"
            if haskey(ENV, stream_key)
                stream_value = parse(Int, ENV[stream_key])
                push!(fields, :(
                    $stream_field::Int64 => (
                        value => $stream_value,
                        access => AccessMode.READABLE
                    )
                ))
            end
        end
    end

    # Add the sub connection count field
    push!(fields, :(
        SubDataConnectionCount::Int64 => (
            value => $connection_count,
            access => AccessMode.READABLE
        )
    ))

    return esc(Expr(:block, fields...))
end

# Helper macro to generate fields from PUB_DATA_URI_* environment variables
macro generate_pub_data_uri_fields()
    fields = []
    connection_count = 0

    # Scan environment at macro expansion time
    for (key, value) in ENV
        if startswith(key, "PUB_DATA_URI_")
            connection_count += 1
            # Extract index number
            idx = parse(Int, replace(key, "PUB_DATA_URI_" => ""))
            uri_field = Symbol("PubDataURI$(idx)")
            stream_field = Symbol("PubDataStreamID$(idx)")

            # Add URI field (read-only)
            push!(fields, :(
                $uri_field::String => (
                    value => $value,
                    access => AccessMode.READABLE
                )
            ))

            # Add corresponding stream ID field (read-only)
            stream_key = "PUB_DATA_STREAM_$(idx)"
            if haskey(ENV, stream_key)
                stream_value = parse(Int, ENV[stream_key])
                push!(fields, :(
                    $stream_field::Int64 => (
                        value => $stream_value,
                        access => AccessMode.READABLE
                    )
                ))
            end
        end
    end

    # Add the pub connection count field
    push!(fields, :(
        PubDataConnectionCount::Int64 => (
            value => $connection_count,
            access => AccessMode.READABLE
        )
    ))

    return esc(Expr(:block, fields...))
end
