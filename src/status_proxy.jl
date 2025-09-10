"""
    StatusProxy

Proxy for publishing events and state changes to the status stream.

Contains minimal components needed for Aeron message publishing with SBE encoding.
The `position_ptr` enables efficient buffer positioning during encoding operations.

# Fields
- `position_ptr::Base.RefValue{Int64}`: current buffer position for SBE encoding
- `publication::Aeron.ExclusivePublication`: dedicated Aeron publication stream
- `buffer::Vector{UInt8}`: reusable buffer for message construction
"""
struct StatusProxy
    position_ptr::Base.RefValue{Int64}
    publication::Aeron.ExclusivePublication
    buffer::Vector{UInt8}
    function StatusProxy(publication::Aeron.ExclusivePublication)
        new(Ref{Int64}(0), publication, zeros(UInt8, 1024))
    end
end

"""
    publish_status_event(proxy, field, value, tag, correlation_id, timestamp_ns)

Publish an event to the status stream with SBE encoding.

Handles buffer claiming, message encoding, and publication to Aeron stream.
Returns `nothing` on success or when no subscribers are present.
"""
function publish_status_event(
    proxy::StatusProxy,
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64) where {T<:Union{AbstractString,Char,Nothing,Real,Symbol,Tuple}}

    # Calculate buffer length needed
    len = sbe_encoded_length(MessageHeader) +
          sbe_block_length(EventMessage) +
          SpidersMessageCodecs.value_header_length(EventMessage) +
          sizeof(value)

    # Try to claim the buffer
    claim = try_claim(proxy.publication, len)
    if isnothing(claim)
        # No subscribers - skip publishing
        return nothing
    end

    # Create the message encoder
    encoder = EventMessageEncoder(Aeron.buffer(claim); position_ptr=proxy.position_ptr)
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

function publish_status_event(
    proxy::StatusProxy,
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64) where {T<:Exception}

    msg = string(value)
    len = sizeof(msg)

    # Create the message encoder
    encoder = EventMessageEncoder(proxy.buffer; position_ptr=proxy.position_ptr)
    header = SpidersMessageCodecs.header(encoder)

    # Fill in the message
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.key!(encoder, field)
    SpidersMessageCodecs.format!(encoder, convert(SpidersMessageCodecs.Format.SbeEnum, String))
    @inbounds SpidersMessageCodecs.value_length!(encoder, len)
    # value_length! doesn't increment the position, so we need to do it manually
    SpidersMessageCodecs.sbe_position!(encoder, sbe_position(encoder) + SpidersMessageCodecs.value_header_length(encoder))
    event_message = convert(AbstractArray{UInt8}, encoder)

    # Offer in the correct order
    offer(proxy.publication,
        (
            event_message,
            codeunits(msg)
        )
    )

    nothing
end

"""
    publish_status_event(proxy, field, value::AbstractArray, tag, correlation_id, timestamp_ns)

Publish an array event to the status stream with SBE tensor encoding.

Uses tensor message format for efficient array data transmission.
"""
function publish_status_event(
    proxy::StatusProxy,
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64) where {T<:AbstractArray}

    # Encode the buffer headers in reverse order

    # Calculate array data length
    len = sizeof(eltype(value)) * length(value)

    # Create tensor message
    tensor = TensorMessageEncoder(proxy.buffer; position_ptr=proxy.position_ptr)
    header = SpidersMessageCodecs.header(tensor)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.format!(tensor, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(tensor, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(tensor, Int32.(size(value)))
    SpidersMessageCodecs.origin!(tensor, nothing)
    @inbounds SpidersMessageCodecs.values_length!(tensor, len)
    SpidersMessageCodecs.sbe_position!(tensor, sbe_position(tensor) + SpidersMessageCodecs.values_header_length(tensor))
    tensor_message = convert(AbstractArray{UInt8}, tensor)
    len += length(tensor_message)

    event = EventMessageEncoder(proxy.buffer, sbe_position(tensor); position_ptr=proxy.position_ptr)
    header = SpidersMessageCodecs.header(event)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.format!(event, SpidersMessageCodecs.Format.SBE)
    SpidersMessageCodecs.key!(event, field)
    @inbounds SpidersMessageCodecs.value_length!(event, len)
    # value_length! doesn't increment the position, so we need to do it manually
    SpidersMessageCodecs.sbe_position!(event, sbe_position(event) + SpidersMessageCodecs.value_header_length(event))
    event_message = convert(AbstractArray{UInt8}, event)

    # Offer in the correct order
    offer(proxy.publication,
        (
            event_message,
            tensor_message,
            vec(reinterpret(UInt8, value))
        )
    )

    nothing
end

"""
    publish_state_change(proxy, new_state, tag, correlation_id, timestamp_ns)

Publish a state change event using the status proxy.

Convenience function that publishes a `:StateChange` event with the new state value.
"""
function publish_state_change(proxy::StatusProxy, new_state::Symbol, tag::String, correlation_id::Int64, timestamp_ns::Int64)
    return publish_status_event(proxy, :StateChange, new_state, tag, correlation_id, timestamp_ns)
end

"""
    publish_event_response(proxy, event, value, tag, correlation_id, timestamp_ns)

Publish an event response using the status proxy.

Used to respond to control events with result data or acknowledgments.
"""
function publish_event_response(proxy::StatusProxy, event::Symbol, value, tag::String, correlation_id::Int64, timestamp_ns::Int64)
    return publish_status_event(proxy, event, value, tag, correlation_id, timestamp_ns)
end
