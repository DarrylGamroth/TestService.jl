"""
State machine utility functions for property handling and message processing.

Contains helper functions used across different agent states for property
decoding, value assignment, and event handling operations.
"""

"""
    decode_property_value(message, ::Type{T}) where {T<:AbstractArray}

Decode an array property value from a tensor message.

Extracts tensor data from SBE message format and reconstructs the array.
"""
function decode_property_value(message, ::Type{T}) where {T<:AbstractArray}
    tensor_message = SpidersMessageCodecs.value(message, SpidersMessageCodecs.TensorMessage)
    SpidersMessageCodecs.decode(tensor_message, T)
end

"""
    decode_property_value(message, ::Type{T}) where {T}

Decode a scalar property value from an event message.

Generic fallback for non-array types including strings, numbers, and symbols.
"""
function decode_property_value(message, ::Type{T}) where {T}
    SpidersMessageCodecs.value(message, T)
end

"""
    set_property_value!(properties, event, value, ::Type{T}) where {T<:AbstractArray}

Set an array property value with collection to ensure ownership.

Collects the array value to avoid aliasing issues with message buffers.
"""
function set_property_value!(properties::AbstractStaticKV, event, value, ::Type{T}) where {T<:AbstractArray}
    # If the property is an array, we need to collect it
    # TODO: It would be better to copy the contents instead of collecting
    # to avoid unnecessary allocations
    setindex!(properties, collect(value), event)
end

"""
    set_property_value!(properties, event, value, ::Type{T}) where {T<:AbstractString}

Set a string property value with collection to ensure ownership.

Collects the string value to avoid aliasing with message buffer data.
"""
function set_property_value!(properties::AbstractStaticKV, event, value, ::Type{T}) where {T<:AbstractString}
    # If the property is a string, we need to collect it
    # TODO: It would be better to copy the contents instead of collecting
    # to avoid unnecessary allocations
    setindex!(properties, collect(value), event)
end

"""
    set_property_value!(properties, event, value, ::Type{T}) where {T}

Set a scalar property value directly without copying.

Generic fallback for bits types that can be stored directly.
"""
# Generic fallback for all other types (bits types, etc.)
function set_property_value!(properties::AbstractStaticKV, event, value, ::Type{T}) where {T}
    setindex!(properties, value, event)
end

"""
    handle_property_write(sm, event, message)

Handle a property write request by decoding and storing the new value.

Decodes the property value from the message, updates the property store,
and publishes a status event confirming the change.
"""
function handle_property_write(sm::RtcAgent, event, message)
    prop_type = keytype(sm.properties, event)
    value = decode_property_value(message, prop_type)
    
    set_property_value!(sm.properties, event, value, prop_type)
    publish_status_event(sm, event, value, sm.source_correlation_id)
end

"""
    handle_property_read(sm, event, _)

Handle a property read request by publishing the current value.

Checks if the property exists and publishes its current value as a status event.
"""
function handle_property_read(sm::RtcAgent, event, _)
    if isset(sm.properties, event)
        value = sm.properties[event]
        publish_status_event(sm, event, value, sm.source_correlation_id)
    end
end
