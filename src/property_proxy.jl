"""
    PropertyProxy

Proxy for publishing property values to multiple output streams.

Contains minimal components for Aeron message publishing with stream selection.
The `publications` vector enables routing to different streams based on index.

# Fields
- `position_ptr::Base.RefValue{Int64}`: current buffer position for SBE encoding
- `publications::Vector{Aeron.ExclusivePublication}`: multiple output streams
- `buffer::Vector{UInt8}`: reusable buffer for message construction
"""
struct PropertyProxy
    position_ptr::Base.RefValue{Int64}
    publications::Vector{Aeron.ExclusivePublication}
    buffer::Vector{UInt8}
    function PropertyProxy(publications::Vector{Aeron.ExclusivePublication})
        new(Ref{Int64}(0), publications, zeros(UInt8, 1024))
    end
end

"""
    publish_property(proxy, stream_index, field, value, tag, correlation_id, timestamp_ns)

Publish a property value to the specified output stream with SBE encoding.

Routes to the output stream by index and handles buffer claiming and message encoding.
Returns `nothing` on success or when no subscribers are present.

# Arguments
- `stream_index::Int`: 1-based index into the publications vector
- `field::Symbol`: property field name
- `value`: property value (string, char, number, symbol, or tuple)
- `tag::AbstractString`: message tag for identification
- `correlation_id::Int64`: unique correlation identifier
- `timestamp_ns::Int64`: message timestamp in nanoseconds
"""
function publish_property(
    proxy::PropertyProxy,
    stream_index::Int,
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64) where {T<:Union{AbstractString,Char,Real,Nothing,Symbol,Tuple}}

    # Calculate buffer length needed
    len = sbe_encoded_length(MessageHeader) +
          sbe_block_length(EventMessage) +
          SpidersMessageCodecs.value_header_length(EventMessage) +
          sizeof(value)

    # Try to claim the buffer
    claim = try_claim(proxy.publications[stream_index], len)
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

"""
    publish_property(proxy, stream_index, field, value::AbstractArray, tag, correlation_id, timestamp_ns)

Publish an array property value with SBE tensor encoding.

Routes to the specified output stream by index with efficient tensor format.
"""
function publish_property(
    proxy::PropertyProxy,
    stream_index::Int,
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64) where {T<:AbstractArray}

    # Calculate array data length
    len = sizeof(eltype(value)) * length(value)

    # Create tensor message
    encoder = TensorMessageEncoder(proxy.buffer; position_ptr=proxy.position_ptr)
    header = SpidersMessageCodecs.header(encoder)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, field)
    SpidersMessageCodecs.format!(encoder, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(encoder, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(encoder, Int32.(size(value)))
    SpidersMessageCodecs.origin!(encoder, nothing)
    @inbounds SpidersMessageCodecs.values_length!(encoder, len)
    SpidersMessageCodecs.sbe_position!(encoder, sbe_position(encoder) + SpidersMessageCodecs.values_header_length(encoder))
    tensor_message = convert(AbstractArray{UInt8}, encoder)

    # Offer the combined message
    offer(proxy.publications[stream_index],
        (
            tensor_message,
            vec(reinterpret(UInt8, value))
        )
    )

    nothing
end

"""
    publish_property_update(proxy, config, properties, tag, correlation_id, now)

Publish a property update with strategy evaluation and timing control.

Evaluates the publication strategy to determine if the property should be published
at the current time, then handles the publication and updates timing state.
"""
function publish_property_update(proxy::PropertyProxy, config::PublicationConfig, properties::AbstractStaticKV, tag::String, correlation_id::Int64, now::Int64)
    property_timestamp_ns = last_update(properties, config.field)
    if !should_publish(config.strategy, config.last_published_ns,
                      config.next_scheduled_ns, property_timestamp_ns, now)
        return 0
    end

    # Use proxy directly with business logic parameters
    publish_property(proxy, config.stream_index, config.field, properties[config.field],
                    tag, correlation_id, now)

    config.last_published_ns = now
    config.next_scheduled_ns = next_time(config.strategy, now)
    return 1
end
