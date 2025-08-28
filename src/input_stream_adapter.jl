struct InputStreamAdapter
    subscription::Aeron.Subscription
    assembler::Aeron.FragmentAssembler
end

"""
    InputStreamAdapter(subscription::Aeron.Subscription, agent)

Create an input stream adapter with the given subscription.
The adapter encapsulates the FragmentAssembler and message processing logic.
Agent type is inferred by the JIT compiler.
"""
function InputStreamAdapter(subscription::Aeron.Subscription, agent)
    # Create the fragment handler that dispatches to data_handler
    fragment_handler = Aeron.FragmentHandler(agent) do agent, buffer, _
        message = TensorMessageDecoder(buffer; position_ptr=agent.position_ptr)
        header = SpidersMessageCodecs.header(message)
        agent.correlation_id = SpidersMessageCodecs.correlationId(header)
        tag = SpidersMessageCodecs.tag(header, Symbol)

        dispatch!(agent, tag, message)
        nothing
    end
    assembler = Aeron.FragmentAssembler(fragment_handler)

    InputStreamAdapter(subscription, assembler)
end

"""
    poll(adapter::InputStreamAdapter, limit::Int = 10) -> Int

Poll the input stream for incoming messages.
Returns the number of fragments processed.
"""
function poll(adapter::InputStreamAdapter, limit::Int=10)
    return Aeron.poll(adapter.subscription, adapter.assembler, limit)
end

"""
    poll(adapters::Vector{InputStreamAdapter}, limit::Int = 10) -> Int

Poll all input stream adapters for incoming data messages.
Returns the total number of fragments processed across all adapters.
Uses the same polling strategy as the original input_poller.
"""
function poll(adapters::Vector{InputStreamAdapter}, limit::Int=10)
    work_count = 0

    while true
        all_streams_empty = true

        for adapter in adapters
            fragments_read = poll(adapter, limit)
            if fragments_read > 0
                all_streams_empty = false
            end
            work_count += fragments_read
        end

        if all_streams_empty
            break
        end
    end
    return work_count
end
