"""
    CommunicationResources

Manages all Aeron communication streams and buffers for an RTC agent.

# Fields
- `status_stream::Aeron.Publication` - Stream for publishing agent status
- `control_stream::Aeron.Subscription` - Stream for receiving control commands
- `input_streams::Vector{Aeron.Subscription}` - Streams for receiving input data
- `output_streams::Vector{Aeron.Publication}` - Streams for publishing output data
- `buf::Vector{UInt8}` - Shared buffer for message serialization
"""
struct CommunicationResources
    # Aeron streams
    status_stream::Aeron.Publication
    control_stream::Aeron.Subscription
    input_streams::Vector{Aeron.Subscription}
    output_streams::Vector{Aeron.Publication}

    # Shared buffer
    buf::Vector{UInt8}

    function CommunicationResources(client::Aeron.Client, p::Properties)
        status_uri = p[:StatusURI]
        status_stream_id = p[:StatusStreamID]
        status_stream = Aeron.add_publication(client, status_uri, status_stream_id)

        control_uri = p[:ControlURI]
        control_stream_id = p[:ControlStreamID]
        control_stream = Aeron.add_subscription(client, control_uri, control_stream_id)

        input_streams = Aeron.Subscription[]

        # Get the number of sub data connections from properties
        sub_data_connection_count = p[:SubDataConnectionCount]

        # Create subscriptions for each sub data URI/stream pair
        for i in 1:sub_data_connection_count
            uri_key = Symbol("SubDataURI$i")
            stream_id_key = Symbol("SubDataStreamID$i")

            if haskey(p, uri_key) && haskey(p, stream_id_key)
                uri = p[uri_key]
                stream_id = p[stream_id_key]
                subscription = Aeron.add_subscription(client, uri, stream_id)
                push!(input_streams, subscription)
                @info "Created subscription $i: $uri (stream ID: $stream_id)"
            end
        end

        # Initialize output streams registry and buffer
        output_streams = Aeron.Publication[]

        # Set up PubData publications
        if haskey(p, :PubDataConnectionCount)
            pub_data_connection_count = p[:PubDataConnectionCount]

            # Resize the vector to accommodate all publications
            resize!(output_streams, pub_data_connection_count)

            for i in 1:pub_data_connection_count
                uri_key = Symbol("PubDataURI$i")
                stream_id_key = Symbol("PubDataStreamID$i")

                if haskey(p, uri_key) && haskey(p, stream_id_key)
                    uri = p[uri_key]
                    stream_id = p[stream_id_key]
                    publication = Aeron.add_publication(client, uri, stream_id)
                    output_streams[i] = publication
                    @info "Created publication $i: $uri (stream ID: $stream_id)"
                else
                    @warn "Missing URI or stream ID for pub data connection $i"
                end
            end
        else
            @info "No PubDataConnectionCount found in properties, no publications created"
        end

        buf = Vector{UInt8}(undef, 1 << 23)  # Default buffer size

        new(
            status_stream,
            control_stream,
            input_streams,
            output_streams,
            buf
        )
    end
end

"""
    Base.close(c::CommunicationResources)

Close all Aeron streams managed by this communication resource.
"""
function Base.close(c::CommunicationResources)
    for stream in c.output_streams
        close(stream)
    end
    for stream in c.input_streams
        close(stream)
    end
    close(c.control_stream)
    close(c.status_stream)
end

"""
    Base.isopen(c::CommunicationResources) -> Bool

Check if the communication resources are open by checking the status stream.
"""
Base.isopen(c::CommunicationResources) = isopen(c.status_stream)
