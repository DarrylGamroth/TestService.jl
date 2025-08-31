"""
Property proxy for publishing property values to multiple output streams.
Handles all outbound property communication following the Aeron proxy pattern.
"""

# Note: status_proxy.jl is included by rtcagent.jl, so publish_value is available

# =============================================================================
# Property Proxy Functions
# =============================================================================

"""
Publish a property value to a specific output stream.
"""
function publish_property(agent::RtcAgent, stream_index::Int, field::Symbol, value)
    # Validate stream index
    if stream_index < 1 || stream_index > length(agent.comms.output_streams)
        throw(BoundsError("Stream index $stream_index out of range (1:$(length(agent.comms.output_streams)))"))
    end
    
    # Validate field exists in properties
    if !haskey(agent.properties, field)
        throw(KeyError("Property $field not found in agent"))
    end
    
    correlation_id = next_id(agent.id_gen)
    timestamp = time_nanos(agent.clock)
    publication = agent.comms.output_streams[stream_index]
    
    return publish_value(
        field, value, agent.properties[:Name], correlation_id, timestamp,
        publication, agent.comms.buf, agent.position_ptr
    )
end

"""
Publish a single property update with strategy evaluation.
Consolidates the property publishing logic from rtcagent.jl.
"""
function publish_property_update(agent::RtcAgent, config::PublicationConfig)
    now = time_nanos(agent.clock)
    
    property_timestamp_ns = last_update(agent.properties, config.field)
    if !should_publish(config.strategy, config.last_published_ns, 
                      config.next_scheduled_ns, property_timestamp_ns, now)
        return 0
    end
    
    # Use proxy function for clean separation of concerns
    publish_property(agent, config.stream_index, 
                    config.field, agent.properties[config.field])
    
    config.last_published_ns = now
    config.next_scheduled_ns = next_time(config.strategy, now)
    return 1
end

# =============================================================================
# Future Extension Point: Custom Property Encoders
# =============================================================================

# When different SBE encoders are needed:
# struct PropertyProxy{E<:AbstractEncoder}
#     agent_name::String
#     encoder::E
#     correlation_id_generator::SnowflakeIdGenerator
#     clock::AbstractClock
#     buffer::Vector{UInt8}
#     position_ptr::Ref{Int64}
#     publications::Vector{Aeron.Publication}
# end
