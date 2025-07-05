# Core Publication System
#
# This module provides the core publication functionality for sending property
# values to Aeron streams using different message formats.

# Communication management functions
"""
    setup_publications!(properties, client::Aeron.Client) -> Vector{Aeron.Publication}

Set up Aeron publications for all PubDataURI fields in properties.
Returns a vector of Aeron publications indexed by PubData index.
"""
function setup_publications!(properties, client::Aeron.Client)
    output_streams = Aeron.Publication[]

    # Get the number of pub data connections from properties
    if haskey(properties, :PubDataConnectionCount)
        pub_data_connection_count = properties[:PubDataConnectionCount]

        # Create publications for each pub data URI/stream pair
        for i in 1:pub_data_connection_count
            uri_prop = Symbol("PubDataURI$(i)")
            stream_prop = Symbol("PubDataStreamID$(i)")

            # Check if both URI and stream ID properties exist
            if haskey(properties, uri_prop) && haskey(properties, stream_prop)
                # Read URI and stream ID from properties
                uri = properties[uri_prop]
                stream_id = properties[stream_prop]

                # Create the publication
                publication = Aeron.add_publication(client, uri, stream_id)
                push!(output_streams, publication)

                @info "Created publication for pub data stream" uri = uri stream_id = stream_id index = i
            else
                throw(ArgumentError("Missing required properties for pub data connection $i: $uri_prop and $stream_prop"))
            end
        end
    else
        @info "No PubDataConnectionCount found in properties, no publications created"
    end

    return output_streams
end

"""
    close_publications!(output_streams::Vector{Aeron.Publication})

Close Aeron publications for pub data streams.
"""
function close_publications!(output_streams::Vector{Aeron.Publication})
    for (index, publication) in enumerate(output_streams)
        close(publication)
        @info "Closed publication" index = index
    end
    empty!(output_streams)
    @info "Closed all publications"
end
