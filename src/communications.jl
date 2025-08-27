"""
    try_claim(publication, length, max_attempts=10)

Try to claim a buffer from the stream with retries.
Returns the claim on success, nothing if no subscribers.
Throws ClaimBufferError if max attempts exceeded due to persistent back pressure.
"""
function try_claim(publication, length, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        claim, result = Aeron.try_claim(publication, length)
        if result > 0
            return claim
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            attempts -= 1
            if attempts > 0
                continue
            else
                throw(ClaimBufferError(
                    string(publication),
                    length,
                    max_attempts,
                    max_attempts
                ))
            end
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            # No subscribers connected - this is normal in some cases
            return nothing
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        else
            attempts -= 1
        end
    end
    throw(ClaimBufferError(
        string(publication),
        length,
        max_attempts - attempts,
        max_attempts
    ))
end

"""
    offer(publication, buffer, max_attempts=10)

Offer a buffer to the stream with retries.
Returns nothing on success or when no subscribers (both are normal cases).
Throws PublicationBackPressureError if max attempts exceeded due to persistent back pressure.
"""
function offer(publication, buffer, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        result = Aeron.offer(publication, buffer)
        if result > 0
            return nothing
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            attempts -= 1
            if attempts > 0
                continue
            else
                throw(PublicationBackPressureError(
                    string(publication),
                    max_attempts,
                    max_attempts
                ))
            end
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            # No subscribers connected - this is normal, just return
            return nothing
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        else
            attempts -= 1
        end
    end
    throw(PublicationBackPressureError(
        string(publication),
        max_attempts - attempts,
        max_attempts
    ))
end

"""
    publish_value(field::Symbol, value, tag::AbstractString, correlation_id::Int64, timestamp_ns::Int64, publication, buffer::AbstractArray{UInt8}, position_ptr::Base.RefValue{Int64})

Publish a scalar value to the specified stream using EventMessage format.
"""
function publish_value(
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    _::AbstractArray{UInt8},
    position_ptr::Base.RefValue{Int64}) where {T<:Union{AbstractString,Char,Real,Symbol,Tuple}}

    # Calculate buffer length needed
    len = sbe_encoded_length(MessageHeader) +
          sbe_block_length(EventMessage) +
          SpidersMessageCodecs.value_header_length(EventMessage) +
          sizeof(value)

    # Try to claim the buffer
    claim = try_claim(publication, len)
    if isnothing(claim)
        # No subscribers - skip publishing
        return nothing
    end

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

    nothing
end

"""
    publish_value(field::Symbol, value::AbstractArray, tag::AbstractString, correlation_id::Int64, timestamp_ns::Int64, publication, buffer::AbstractArray{UInt8}, position_ptr::Base.RefValue{Int64})

Publish an array value to the specified stream using TensorMessage format.
"""
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
    len = sizeof(eltype(value)) * length(value)

    # Create tensor message
    encoder = TensorMessageEncoder(buffer; position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(encoder)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.format!(encoder, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(encoder, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(encoder, Int32.(size(value)))
    SpidersMessageCodecs.origin!(encoder, nothing)
    SpidersMessageCodecs.values_length!(encoder, len)
    SpidersMessageCodecs.sbe_position!(encoder, sbe_position(encoder) + SpidersMessageCodecs.values_header_length(encoder))
    tensor_message = convert(AbstractArray{UInt8}, encoder)

    # Offer the combined message
    offer(publication,
        (
            tensor_message,
            vec(reinterpret(UInt8, value))
        )
    )

    nothing
end

function publish_event(
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    buffer::AbstractArray{UInt8},
    position_ptr::Base.RefValue{Int64}) where {T<:Union{AbstractString,Char,Real,Symbol,Tuple}}
    publish_value(
        field,
        value,
        tag,
        correlation_id,
        timestamp_ns,
        publication,
        buffer,
        position_ptr
    )
end


"""
    publish_event(field::Symbol, value::AbstractArray, tag::AbstractString, correlation_id::Int64, timestamp_ns::Int64, publication, buffer::AbstractArray{UInt8}, position_ptr::Base.RefValue{Int64})

Publish an array value to the specified stream using TensorMessage format.
"""
function publish_event(
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    buffer::AbstractArray{UInt8},
    position_ptr::Base.RefValue{Int64}) where {T<:AbstractArray}

    # Encode the buffer headers in reverse order

    # Calculate array data length
    len = sizeof(eltype(value)) * length(value)

    # Create tensor message
    tensor = TensorMessageEncoder(buffer; position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(tensor)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.format!(tensor, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(tensor, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(tensor, Int32.(size(value)))
    SpidersMessageCodecs.origin!(tensor, nothing)
    SpidersMessageCodecs.values_length!(tensor, len)
    SpidersMessageCodecs.sbe_position!(tensor, sbe_position(tensor) + SpidersMessageCodecs.values_header_length(tensor))
    tensor_message = convert(AbstractArray{UInt8}, tensor)
    len += length(tensor_message)

    event = EventMessageEncoder(buffer, sbe_position(tensor); position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(event)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.format!(event, SpidersMessageCodecs.Format.SBE)
    SpidersMessageCodecs.key!(event, field)
    SpidersMessageCodecs.value_length!(event, len)
    # value_length! doesn't increment the position, so we need to do it manually
    SpidersMessageCodecs.sbe_position!(event, sbe_position(event) + SpidersMessageCodecs.value_header_length(event))
    event_message = convert(AbstractArray{UInt8}, event)

    # Offer in the correct order
    offer(publication,
        (
            event_message,
            tensor_message,
            vec(reinterpret(UInt8, value))
        )
    )
    
    nothing
end
