# Core Publication System
#
# This module provides the core publication functionality for sending property
# values to Aeron streams using different message formats.

# Property value publishing
"""
    publish_value(field::Symbol, value, tag::AbstractString, correlation_id::Int64, timestamp_ns::Int64, p, buffer::AbstractArray{UInt8}, position_ptr::Base.RefValue{Int64})

Publish a value to the specified stream.
"""
function publish_value(
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    buffer::AbstractArray{UInt8},
    position_ptr::Base.RefValue{Int64}) where {T<:Union{AbstractString,Char,Real,Symbol,Tuple}}

    # Calculate buffer length needed
    len = sbe_encoded_length(MessageHeader) +
          sbe_block_length(EventMessage) +
          SpidersMessageCodecs.value_header_length(EventMessage) +
          sizeof(value)

    # Try to claim the buffer
    claim = try_claim(publication, len)

    # Create the message encoder
    encoder = EventMessageEncoder(buffer(claim); position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(encoder)

    # Fill in the message
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.key!(encoder, field)
    encode(encoder, value)

    # Commit the message
    Aeron.commit(claim)

    return true
end

function publish_value(
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    buffer::AbstractArray{UInt8},
    position_ptr::Base.RefValue{Int64}) where {T<:AbstractArray}

    # Calculate array data length
    values_length = sizeof(eltype(value)) * length(value)

    # Create tensor message
    encoder = TensorMessageEncoder(buffer; position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(encoder)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, field)
    SpidersMessageCodecs.format!(encoder, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(encoder, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(encoder, Int32.(size(value)))
    SpidersMessageCodecs.origin!(encoder, nothing)
    SpidersMessageCodecs.values_length!(encoder, values_length)
    SpidersMessageCodecs.sbe_position!(encoder, sbe_position(encoder) + SpidersMessageCodecs.values_header_length(encoder))
    tensor_message = convert(AbstractArray{UInt8}, encoder)

    # Offer the combined message
    offer(publication,
        (
            tensor_message,
            vec(reinterpret(UInt8, value))
        )
    )
end

# Helper functions for Aeron operations with retries
"""
    try_claim(p, len, max_attempts=10)

Try to claim a buffer from the stream with retries.
"""
function try_claim(p, length, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        claim, result = Aeron.try_claim(p, length)
        if result > 0
            return claim
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            attempts -= 1
            continue
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            throw(ErrorException("Publication not connected"))
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        end
        attempts -= 1
    end
    throw(ErrorException("Failed to claim buffer after $max_attempts attempts"))
end

"""
    offer(p, buffer, max_attempts=10)

Offer a buffer to the stream with retries.
Returns nothing on success, throws exception on connection error.
"""
function offer(p, buffer, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        result = Aeron.offer(p, buffer)
        if result > 0
            return
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            attempts -= 1
            continue
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            throw(ErrorException("Publication not connected"))
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        end
        attempts -= 1
    end
end

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

# Export core publication interface
export publish_value, try_claim, offer
export setup_publications!, close_publications!
