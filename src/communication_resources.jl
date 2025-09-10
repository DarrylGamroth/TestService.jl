"""
    CommunicationResources

Manage all Aeron communication streams for an RTC agent.

Contains status, control, input, and output streams configured from environment
properties. Streams are ordered by access frequency for optimal performance.

# Fields
- `input_streams::Vector{Aeron.Subscription}`: streams for receiving input data
- `output_streams::Vector{Aeron.ExclusivePublication}`: streams for output data
- `status_stream::Aeron.ExclusivePublication`: stream for publishing agent status
- `control_stream::Aeron.Subscription`: stream for receiving control commands
"""
struct CommunicationResources
    input_streams::Vector{Aeron.Subscription}
    output_streams::Vector{Aeron.ExclusivePublication}
    status_stream::Aeron.ExclusivePublication
    control_stream::Aeron.Subscription

    function CommunicationResources(client::Aeron.Client, properties::AbstractStaticKV)
        status_uri = properties[:StatusURI]
        status_stream_id = properties[:StatusStreamID]
        status_stream = Aeron.add_exclusive_publication(client, status_uri, status_stream_id)

        control_uri = properties[:ControlURI]
        control_stream_id = properties[:ControlStreamID]
        control_stream = Aeron.add_subscription(client, control_uri, control_stream_id)

        input_streams = Aeron.Subscription[]

        # Get the number of sub data connections from properties
        sub_data_connection_count = properties[:SubDataConnectionCount]

        # Create subscriptions for each sub data URI/stream pair
        for i in 1:sub_data_connection_count
            uri_key = Symbol("SubDataURI$i")
            stream_id_key = Symbol("SubDataStreamID$i")

            if haskey(properties, uri_key) && haskey(properties, stream_id_key)
                uri = properties[uri_key]
                stream_id = properties[stream_id_key]
                subscription = Aeron.add_subscription(client, uri, stream_id)
                push!(input_streams, subscription)
                @info "Created subscription $i: $uri (stream ID: $stream_id)"
            end
        end

        # Initialize output streams registry and buffer
        output_streams = Aeron.ExclusivePublication[]

        # Set up PubData publications
        if haskey(properties, :PubDataConnectionCount)
            pub_data_connection_count = properties[:PubDataConnectionCount]

            # Resize the vector to accommodate all publications
            resize!(output_streams, pub_data_connection_count)

            for i in 1:pub_data_connection_count
                uri_key = Symbol("PubDataURI$i")
                stream_id_key = Symbol("PubDataStreamID$i")

                if haskey(properties, uri_key) && haskey(properties, stream_id_key)
                    uri = properties[uri_key]
                    stream_id = properties[stream_id_key]
                    publication = Aeron.add_exclusive_publication(client, uri, stream_id)
                    output_streams[i] = publication
                    @info "Created publication $i: $uri (stream ID: $stream_id)"
                else
                    @warn "Missing URI or stream ID for pub data connection $i"
                end
            end
        else
            @info "No PubDataConnectionCount found in properties, no publications created"
        end

        new(input_streams, output_streams, status_stream, control_stream)
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
