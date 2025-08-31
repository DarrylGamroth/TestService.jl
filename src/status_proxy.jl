"""
Status proxy for publishing events and state changes to status stream.
Handles all outbound status communication following the Aeron proxy pattern.
Contains the core publish_value and publish_event functions used by all proxies.
"""

# =============================================================================
# Core Publishing Functions (moved from communications.jl)
# =============================================================================

"""
Publish a scalar value to an Aeron stream with SBE encoding.
Core proxy function that encodes application types to Aeron messages.
"""
function publish_value(
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    _::AbstractArray{UInt8},
    position_ptr::Base.RefValue{Int64}) where {T<:Union{AbstractString,Char,Real,Symbol,Tuple}}

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
    encoder = EventMessageEncoder(buffer(claim); position_ptr=position_ptr)
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
    len = sizeof(eltype(value)) * length(value)

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
    SpidersMessageCodecs.values_length!(encoder, len)
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
Publish an event to an Aeron stream with SBE encoding.
"""
function publish_event(
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    buffer::AbstractArray{UInt8},
    position_ptr::Base.RefValue{Int64}) where {T<:Union{AbstractString,Char,Real,Symbol,Tuple}}
    publish_value(
        field,
        value,
        tag,
        correlation_id,
        timestamp_ns,
        publication,
        buffer,
        position_ptr
    )
end

"""
Publish an array event to an Aeron stream with SBE encoding.
"""
function publish_event(
    field::Symbol,
    value::T,
    tag::AbstractString,
    correlation_id::Int64,
    timestamp_ns::Int64,
    publication,
    buffer::AbstractArray{UInt8},
    position_ptr::Base.RefValue{Int64}) where {T<:AbstractArray}

    # Encode the buffer headers in reverse order

    # Calculate array data length
    len = sizeof(eltype(value)) * length(value)

    # Create tensor message
    tensor = TensorMessageEncoder(buffer; position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(tensor)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.format!(tensor, convert(SpidersMessageCodecs.Format.SbeEnum, eltype(value)))
    SpidersMessageCodecs.majorOrder!(tensor, SpidersMessageCodecs.MajorOrder.COLUMN)
    SpidersMessageCodecs.dims!(tensor, Int32.(size(value)))
    SpidersMessageCodecs.origin!(tensor, nothing)
    SpidersMessageCodecs.values_length!(tensor, len)
    SpidersMessageCodecs.sbe_position!(tensor, sbe_position(tensor) + SpidersMessageCodecs.values_header_length(tensor))
    tensor_message = convert(AbstractArray{UInt8}, tensor)
    len += length(tensor_message)

    event = EventMessageEncoder(buffer, sbe_position(tensor); position_ptr=position_ptr)
    header = SpidersMessageCodecs.header(event)
    SpidersMessageCodecs.timestampNs!(header, timestamp_ns)
    SpidersMessageCodecs.correlationId!(header, correlation_id)
    SpidersMessageCodecs.tag!(header, tag)
    SpidersMessageCodecs.format!(event, SpidersMessageCodecs.Format.SBE)
    SpidersMessageCodecs.key!(event, field)
    SpidersMessageCodecs.value_length!(event, len)
    # value_length! doesn't increment the position, so we need to do it manually
    SpidersMessageCodecs.sbe_position!(event, sbe_position(event) + SpidersMessageCodecs.value_header_length(event))
    event_message = convert(AbstractArray{UInt8}, event)

    # Offer in the correct order
    offer(publication,
        (
            event_message,
            tensor_message,
            vec(reinterpret(UInt8, value))
        )
    )
    
    nothing
end

# =============================================================================
# Status Proxy Functions
# =============================================================================

function publish_status_event(agent::RtcAgent, event::Symbol, data, correlation_id::Int64)
    timestamp = time_nanos(agent.clock)
    
    return publish_value(
        event, data, agent.properties[:Name], correlation_id, timestamp,
        agent.comms.status_stream, agent.comms.buf, agent.position_ptr
    )
end

function publish_state_change(agent::RtcAgent, new_state::Symbol, correlation_id::Int64)
    return publish_status_event(agent, :StateChange, new_state, correlation_id)
end

# =============================================================================
# Future Extension Point: Custom Status Encoders
# =============================================================================

# When different SBE encoders are needed:
# struct StatusProxy{E<:AbstractEncoder}
#     agent_name::String
#     encoder::E
#     correlation_id_generator::SnowflakeIdGenerator
#     clock::AbstractClock
#     buffer::Vector{UInt8}
#     position_ptr::Ref{Int64}
#     publication::Aeron.Publication
# end
