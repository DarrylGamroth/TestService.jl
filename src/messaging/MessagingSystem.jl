# MessagingSystem Module
#
# Provides shared utilities for Aeron communication and SBE message encoding.
# Consolidates common patterns from EventSystem and PropertiesSystem.

module MessagingSystem

using Aeron
using SpidersMessageCodecs
using UnsafeArrays

export publish_value, try_claim, offer, send_event_response

# Core Publication Utilities (consolidated from PropertiesSystem)

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
    encoder = EventMessageEncoder(buffer; position_ptr=position_ptr)
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
    values_length = sizeof(eltype(value)) * length(value)

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

# Core Event Response Utilities (consolidated from EventSystem)
# Note: send_event_response is essentially identical to publish_value but with different parameter names
# Both encode a field/event with a value and publish it

"""
    send_event_response(event::Symbol, value, agent_name::String, correlation_id::Int64, timestamp_ns::Int64, publication, buffer::Vector{UInt8}, position_ptr::Base.RefValue{Int64})

Send an event response using the same pattern as publish_value.
This is essentially identical to publish_value but with parameter names that make sense for event responses.
"""
function send_event_response(
    event::Symbol,
    value,
    agent_name::String,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    buffer::Vector{UInt8},
    position_ptr::Base.RefValue{Int64})
    # This is identical to publish_value for scalar values - just call it directly
    return publish_value(event, value, agent_name, correlation_id, timestamp_ns, publication, buffer, position_ptr)
end

"""
    send_event_response(event::Symbol, value::AbstractArray, agent_name::String, correlation_id::Int64, timestamp_ns::Int64, publication, buffer::Vector{UInt8}, position_ptr::Base.RefValue{Int64})

Send an event response with array data using EventSystem's nested TensorMessage format.
This is different from publish_value because EventSystem wraps TensorMessage inside EventMessage.
"""
function send_event_response(
    event::Symbol,
    value::AbstractArray,
    agent_name::String,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    buffer::Vector{UInt8},
    position_ptr::Base.RefValue{Int64})
    # Encode the buffer in reverse order
    len = sizeof(eltype(value)) * length(value)

    # Use the SBE encoder to create a TensorMessage header
    tensor = TensorMessageEncoder(buffer; position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(tensor)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, agent_name)
    SpidersMessageCodecs.format!(tensor, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(tensor, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(tensor, Int32.(size(value)))
    SpidersMessageCodecs.origin!(tensor, nothing)
    SpidersMessageCodecs.values_length!(tensor, len)
    # values_length! doesn't increment the position, so we need to do it manually
    SpidersMessageCodecs.sbe_position!(tensor, sbe_position(tensor) + SpidersMessageCodecs.values_header_length(tensor))
    tensor_message = convert(AbstractArray{UInt8}, tensor)
    len += length(tensor_message)

    response = EventMessageEncoder(buffer, sbe_position(tensor); position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(response)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, agent_name)
    SpidersMessageCodecs.format!(response, SpidersMessageCodecs.Format.SBE)
    SpidersMessageCodecs.key!(response, event)
    SpidersMessageCodecs.value_length!(response, len)
    # value_length! doesn't increment the position, so we need to do it manually
    SpidersMessageCodecs.sbe_position!(response, sbe_position(response) + SpidersMessageCodecs.value_header_length(response))
    response_message = convert(AbstractArray{UInt8}, response)

    # Offer in the correct order
    offer(publication,
        (
            response_message,
            tensor_message,
            vec(reinterpret(UInt8, value))
        )
    )
    nothing
end

# Helper functions for Aeron operations with retries (consolidated from both systems)

"""
    try_claim(publication, length, max_attempts=10)

Try to claim a buffer from the stream with retries.
"""
function try_claim(publication, length, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        claim, result = Aeron.try_claim(publication, length)
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
    offer(publication, buffer, max_attempts=10)

Offer a buffer to the stream with retries.
Returns nothing on success, throws exception on connection error.
"""
function offer(publication, buffer, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        result = Aeron.offer(publication, buffer)
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

end # module MessagingSystem