# State machine utility functions
# Common helper functions used across different states

"""
    send_event_response(agent::RtcAgent, event, value)

Send an event response from the state machine.
This is a common utility function used across different states to send responses.
"""
@inline function send_event_response(agent::RtcAgent, event, value)
    # Check if communications are initialized
    if isnothing(agent.comms) || isnothing(agent.comms.status_stream)
        @debug "Cannot send event response: communications not initialized" event value
        return 0  # Return a dummy position
    end
    
    return publish_event(
        event,                    # field/event
        value,                    # value - dispatch handles scalar vs array
        agent.properties[:Name],     # agent_name
        agent.correlation_id,        # correlation_id
        time_nanos(agent.clock),     # timestamp_ns
        agent.comms.status_stream,   # publication
        agent.comms.buf,             # buffer
        agent.position_ptr           # position_ptr
    )
end

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
    setindex!(properties, collect(value), event)
end

function set_property_value!(properties, event, value, ::Type{T}) where {T<:AbstractString}
    # If the property is a string, we need to collect it
    # TODO: It would be better to copy the contents instead of collecting
    # to avoid unnecessary allocations
    setindex!(properties, collect(value), event)
end

# Generic fallback for all other types (bits types, etc.)
function set_property_value!(properties, event, value, ::Type{T}) where {T}
    setindex!(properties, value, event)
end

function handle_property_write(sm::RtcAgent, properties, event, message)
    prop_type = keytype(properties, event)
    value = decode_property_value(message, prop_type)
    
    set_property_value!(properties, event, value, prop_type)
    send_event_response(sm, event, value)
end

function handle_property_read(sm::RtcAgent, properties, event, _)
    if isset(properties, event)
        value = properties[event]
        send_event_response(sm, event, value)
    else
        throw(PropertyStore.PropertyNotFoundError(event))
    end
end
