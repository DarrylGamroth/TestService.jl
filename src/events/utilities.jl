# State machine utility functions
# Common helper functions used across different states

function decode_property_value(message, ::Type{T}) where {T<:AbstractArray}
    tensor_message = SpidersMessageCodecs.value(message, SpidersMessageCodecs.TensorMessage)
    SpidersMessageCodecs.decode(tensor_message, T)
end

function decode_property_value(message, ::Type{T}) where {T}
    SpidersMessageCodecs.value(message, T)
end

function set_property_value!(properties, event, value, ::Type{T}) where {T<:AbstractArray}
    # If the property is an array, we need to collect it
    # TODO: It would be better to copy the contents instead of collecting
    # to avoid unnecessary allocations
    setkey!(properties, event, collect(value))
end

function set_property_value!(properties, event, value, ::Type{T}) where {T<:AbstractString}
    # If the property is a string, we need to collect it
    # TODO: It would be better to copy the contents instead of collecting
    # to avoid unnecessary allocations
    setkey!(properties, event, collect(value))
end

# Generic fallback for all other types (bits types, etc.)
function set_property_value!(properties, event, value, ::Type{T}) where {T}
    setkey!(properties, event, value)
end

function handle_property_write(sm::EventManager, properties, event, message)
    prop_type = property_type(properties, event)
    value = decode_property_value(message, prop_type)

    set_property_value!(properties, event, value, prop_type)
    send_event_response(sm, event, value)
end

function handle_property_read(sm::EventManager, properties, event, _)
    value = properties[event]
    send_event_response(sm, event, value)
end
