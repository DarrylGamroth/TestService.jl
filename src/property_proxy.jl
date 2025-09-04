"""
Property proxy for publishing property values to multiple output streams.
Handles all outbound property communication following the Aeron proxy pattern.
"""

# =============================================================================
# Proxy Struct Definition
# =============================================================================

"""
Property proxy struct for dedicated property stream publishing.
Contains only the minimal components needed for Aeron message publishing.
"""
struct PropertyProxy
    position_ptr::Base.RefValue{Int64}
    publications::Vector{Aeron.ExclusivePublication}
    buffer::Vector{UInt8}
    function PropertyProxy(publications::Vector{Aeron.ExclusivePublication})
        new(Ref{Int64}(0), publications, zeros(UInt8, 1024))
    end
end

function publish_property(
    proxy::PropertyProxy,
    stream_index::Int,
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64) where {T<:Union{AbstractString,Char,Real,Symbol,Tuple}}

    if stream_index < 1 || stream_index > length(proxy.publications)
        throw(StreamNotFoundError("PubData$stream_index", stream_index))
    end

    publication = proxy.publications[stream_index]

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
Publish an array value to an Aeron stream with SBE encoding.
"""
function publish_property(
    proxy::PropertyProxy,
    stream_index::Int,
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64) where {T<:AbstractArray}

    if stream_index < 1 || stream_index > length(proxy.publications)
        throw(StreamNotFoundError("PubData$stream_index", stream_index))
    end

    publication = proxy.publications[stream_index]

    # Calculate array data length
    len = sizeof(eltype(value)) * length(value)

    # Create tensor message
    encoder = TensorMessageEncoder(proxy.buffer; position_ptr=proxy.position_ptr)
    header = SpidersMessageCodecs.header(encoder)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.format!(encoder, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(encoder, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(encoder, Int32.(size(value)))
    SpidersMessageCodecs.origin!(encoder, nothing)
    @inbounds SpidersMessageCodecs.values_length!(encoder, len)
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

"""
Publish a single property update with strategy evaluation using the proxy struct interface.
This function contains the business logic for strategy evaluation and publication timing.
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
