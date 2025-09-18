"""
    InputStreamAdapter

Adapter for processing input data messages from Aeron subscription.

Handles fragment assembly and tensor message decoding for data stream processing.
Specialized for tensor message format with position tracking.

Supports late message handling via `:LateMessageThresholdNs` property. 
Late messages dispatch `:LateMessage` events.

# Fields
- `subscription::Aeron.Subscription`: input data stream
- `assembler::Aeron.FragmentAssembler`: fragment reconstruction handler
- `position_ptr::Base.RefValue{Int64}`: SBE decoding position tracker
"""
struct InputStreamAdapter
    subscription::Aeron.Subscription
    assembler::Aeron.FragmentAssembler
    position_ptr::Base.RefValue{Int64}
end

"""
    InputStreamAdapter(subscription::Aeron.Subscription, agent)

Create an input stream adapter with the given subscription.
The adapter encapsulates the FragmentAssembler and message processing logic.
"""
function InputStreamAdapter(subscription::Aeron.Subscription, agent)
    # Create position pointer for this adapter
    position_ptr = Ref{Int64}(0)

    let position_ptr = position_ptr
        # Create the fragment handler that dispatches to data_handler
        fragment_handler = Aeron.FragmentHandler(agent) do agent, buffer, _
            message = TensorMessageDecoder(buffer; position_ptr=position_ptr)
            header = SpidersMessageCodecs.header(message)
            agent.source_correlation_id = SpidersMessageCodecs.correlationId(header)
            tag = SpidersMessageCodecs.tag(header, Symbol)
            dispatch!(agent, tag, message)
            nothing
        end

        # Create late fragment handler that dispatches :LateMessage event
        late_fragment_handler = Aeron.FragmentHandler(agent) do agent, buffer, _
            message = TensorMessageDecoder(buffer; position_ptr=position_ptr)
            header = SpidersMessageCodecs.header(message)
            agent.source_correlation_id = SpidersMessageCodecs.correlationId(header)
            dispatch!(agent, :LateMessage, message)
            nothing
        end

        # Apply late fragment filtering if configured
        final_handler = SpidersLateFragmentFilter(fragment_handler, late_fragment_handler,
            agent.properties[:LateMessageThresholdNs], agent.clock)

        assembler = Aeron.FragmentAssembler(final_handler)

        InputStreamAdapter(subscription, assembler, position_ptr)
    end
end

"""
    poll(adapter::InputStreamAdapter, limit::Int) -> Int

Poll the input stream for incoming messages.
Returns the number of fragments processed.
"""
function poll(adapter::InputStreamAdapter, limit::Int)
    return Aeron.poll(adapter.subscription, adapter.assembler, limit)
end

"""
    poll(adapters::AbstractVector{InputStreamAdapter}, limit::Int) -> Int

Poll all input stream adapters for incoming data messages.
Returns the total number of fragments processed across all adapters.
Each adapter gets polled with the full limit for maximum throughput.
"""
function poll(adapters::AbstractVector{InputStreamAdapter}, limit::Int)
    work_count = 0

    @inbounds for i in 1:length(adapters)
        work_count += poll(adapters[i], limit)
    end

    return work_count
end
