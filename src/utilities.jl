# State machine utility functions
# Common helper functions used across different states

function decode_property_value(message, ::Type{T}) where {T<:AbstractArray}
    tensor_message = SpidersMessageCodecs.value(message, SpidersMessageCodecs.TensorMessage)
    SpidersMessageCodecs.decode(tensor_message, T)
end

function decode_property_value(message, ::Type{T}) where {T}
    SpidersMessageCodecs.value(message, T)
end

function set_property_value!(properties::AbstractStaticKV, event, value, ::Type{T}) where {T<:AbstractArray}
    # If the property is an array, we need to collect it
    # TODO: It would be better to copy the contents instead of collecting
    # to avoid unnecessary allocations
    setindex!(properties, collect(value), event)
end

function set_property_value!(properties::AbstractStaticKV, event, value, ::Type{T}) where {T<:AbstractString}
    # If the property is a string, we need to collect it
    # TODO: It would be better to copy the contents instead of collecting
    # to avoid unnecessary allocations
    setindex!(properties, collect(value), event)
end

# Generic fallback for all other types (bits types, etc.)
function set_property_value!(properties::AbstractStaticKV, event, value, ::Type{T}) where {T}
    setindex!(properties, value, event)
end

function handle_property_write(sm::RtcAgent, event, message)
    prop_type = keytype(sm.properties, event)
    value = decode_property_value(message, prop_type)
    
    set_property_value!(sm.properties, event, value, prop_type)
    publish_status_event(sm, event, value, sm.source_correlation_id)
end

function handle_property_read(sm::RtcAgent, event, _)
    if isset(sm.properties, event)
        value = sm.properties[event]
        publish_status_event(sm, event, value, sm.source_correlation_id)
    end
end
