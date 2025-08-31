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
    buffer::Vector{UInt8}
    publications::Vector{Aeron.Publication}
end

# =============================================================================
# Property Proxy Functions (Direct Proxy Interface)
# =============================================================================

"""
Publish a property value to a specific stream using the proxy struct interface.
"""
function publish_property(proxy::PropertyProxy, stream_index::Int, field::Symbol, value, tag::String, correlation_id::Int64, timestamp_ns::Int64)
    if stream_index < 1 || stream_index > length(proxy.publications)
        throw(StreamNotFoundError("PubData$stream_index", stream_index))
    end
    
    publication = proxy.publications[stream_index]
    return publish_value(
        field, value, tag, correlation_id, timestamp_ns,
        publication, proxy.buffer, proxy.position_ptr
    )
end

"""
Publish a single property update with strategy evaluation using the proxy struct interface.
This function contains the business logic for strategy evaluation and publication timing.
"""
function publish_property_update(proxy::PropertyProxy, config::PublicationConfig, properties, tag::String, id_gen, now::Int64)
    property_timestamp_ns = last_update(properties, config.field)
    if !should_publish(config.strategy, config.last_published_ns, 
                      config.next_scheduled_ns, property_timestamp_ns, now)
        return 0
    end
    
    # Use proxy directly with business logic parameters
    publish_property(proxy, config.stream_index, config.field, properties[config.field],
                    tag, next_id(id_gen), now)
    
    config.last_published_ns = now
    config.next_scheduled_ns = next_time(config.strategy, now)
    return 1
end
