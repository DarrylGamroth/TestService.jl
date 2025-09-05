"""
    ControlStreamAdapter

Adapter for processing control messages from Aeron subscription.

Handles fragment assembly and message decoding for control stream processing.
Uses position tracking for efficient SBE message parsing.

# Fields
- `subscription::Aeron.Subscription`: control message stream
- `assembler::Aeron.FragmentAssembler`: fragment reconstruction handler
- `position_ptr::Base.RefValue{Int64}`: SBE decoding position tracker
"""
struct ControlStreamAdapter
    subscription::Aeron.Subscription
    assembler::Aeron.FragmentAssembler
    position_ptr::Base.RefValue{Int64}
end

"""
    ControlStreamAdapter(subscription::Aeron.Subscription, properties, agent)

Create a control stream adapter with the given subscription.
"""
function ControlStreamAdapter(subscription::Aeron.Subscription, agent)
    # Create position pointer for this adapter
    position_ptr = Ref{Int64}(0)

    let position_ptr = position_ptr
        # Create the fragment handler that dispatches to control_handler
        fragment_handler = Aeron.FragmentHandler(agent) do agent, buffer, _
            # A single buffer may contain several Event messages. Decode each one at a time and dispatch
            offset = 0
            while offset < length(buffer)
                message = EventMessageDecoder(buffer, offset; position_ptr=position_ptr)
                header = SpidersMessageCodecs.header(message)
                agent.source_correlation_id = SpidersMessageCodecs.correlationId(header)
                event = SpidersMessageCodecs.key(message, Symbol)

                dispatch!(agent, event, message)

                offset += sbe_encoded_length(MessageHeader) + sbe_decoded_length(message)
            end
            nothing
        end

        # Apply filtering if configured
        if isset(agent.properties, :ControlFilter)
            message_filter = SpidersTagFragmentFilter(fragment_handler, agent.properties[:ControlFilter])
            assembler = Aeron.FragmentAssembler(message_filter)
        else
            assembler = Aeron.FragmentAssembler(fragment_handler)
        end

        ControlStreamAdapter(subscription, assembler, position_ptr)
    end
end

"""
    poll(adapter::ControlStreamAdapter, limit::Int) -> Int

Poll the control stream for incoming messages.
Returns the number of fragments processed.
"""
function poll(adapter::ControlStreamAdapter, limit::Int)
    return Aeron.poll(adapter.subscription, adapter.assembler, limit)
end
