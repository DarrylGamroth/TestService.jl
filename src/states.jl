# Implement the AbstractHsm ancestor interface for each state
@ancestor ControlStateMachine begin
    :Top => :Root
    :Ready => :Top
    :Stopped => :Ready
    :Processing => :Ready
    :Paused => :Processing
    :Playing => :Processing
    :Error => :Top
    :Exit => :Top
end

@on_event function (sm::ControlStateMachine, state::Root, event::Any, message)
    # @info "Default handler called with event: $(event)"
    properties = sm.properties
    if event in property_names(properties)
        if SpidersMessageCodecs.format(message) == SpidersMessageCodecs.Format.NOTHING
            # If the message has no value, then it is a request for the current value
            _handle_property_read(sm, properties, event, message)
        else
            # Otherwise it's a write request
            _handle_property_write(sm, properties, event, message)
        end
        return Hsm.EventHandled
    end

    # Defer to the ancestor handler
    return Hsm.EventNotHandled
end

# Function barrier for property read operations
function _handle_property_read(sm::ControlStateMachine, properties, event, _)
    value = get_property(properties, event)
    send_event_response(sm, event, value)
end

# Function barrier for property write operations  
function _handle_property_write(sm::ControlStateMachine, properties, event, message)
    prop_type = property_type(properties, event)
    value = SpidersMessageCodecs.value(message, prop_type)
    if isbits(value)
        set_property!(properties, event, value)
    else
        with_property!(properties, event) do v
            v .= value
        end
    end
    send_event_response(sm, event, value)
end

# Top-level state control and message routing
@on_initial function (sm::ControlStateMachine, ::Root)
    Hsm.transition!(sm, :Top)
end

@on_initial function (sm::ControlStateMachine, ::Top)
    Hsm.transition!(sm, :Playing)
end

@on_event function (sm::ControlStateMachine, ::Top, ::Reset, _)
    Hsm.transition!(sm, :Top)
end

@on_event function (sm::ControlStateMachine, ::Top, ::State, message)
    send_event_response(sm, :State, Hsm.current(sm))
    return Hsm.EventHandled
end

@on_event function (sm::ControlStateMachine, ::Top, ::GC, _)
    GC.gc()
    return Hsm.EventHandled
end

@on_event function (sm::ControlStateMachine, ::Top, ::GC_enable_logging, message)
    value = SpidersMessageCodecs.value(message, Bool)
    GC.enable_logging(value)
    return Hsm.EventHandled
end

@on_event function (sm::ControlStateMachine, ::Top, ::Exit, _)
    Hsm.transition!(sm, :Exit)
end

@on_event function (sm::ControlStateMachine, ::Top, ::Properties, message)
    if SpidersMessageCodecs.format(message) == SpidersMessageCodecs.Format.NOTHING
        properties = sm.properties
        for name in property_names(properties)
            value = get_property(properties, name)
            send_event_response(sm, name, value)
        end
        return Hsm.EventHandled
    else
        return Hsm.transition!(sm, :Error)
    end
end

########################

@on_initial function (sm::ControlStateMachine, ::Ready)
    Hsm.transition!(sm, :Stopped)
end

########################

@on_event function (sm::ControlStateMachine, ::Stopped, ::Play, _)
    # Only transition if all properties are set
    if all_properties_set(sm.properties)
        return Hsm.transition!(sm, :Playing)
    end

    return Hsm.EventHandled
end

########################

@on_initial function (sm::ControlStateMachine, ::Processing)
    Hsm.transition!(sm, :Paused)
end

@on_event function (sm::ControlStateMachine, ::Top, ::Dummy, message)
    # This is a placeholder for any processing that might be needed
    return Hsm.EventHandled
end

@on_event function (sm::ControlStateMachine, ::Processing, ::Stop, _)
    Hsm.transition!(sm, :Stopped)
end

@on_event function (sm::ControlStateMachine, ::Playing, ::Pause, _)
    Hsm.transition!(sm, :Paused)
end

@on_event function (sm::ControlStateMachine, ::Paused, ::Play, _)
    Hsm.transition!(sm, :Playing)
end

@on_entry function (sm::ControlStateMachine, ::Exit)
    @info "Exiting..."
    teardown_communications!(sm)
    # Signal the AgentRunner to stop
    throw(AgentTerminationException())
end

@on_entry function (sm::ControlStateMachine, ::Error)
    @info "Error"
end

function setup_communications!(sm::ControlStateMachine)
    status_uri = get_property(sm.properties, :StatusURI)
    status_stream_id = get_property(sm.properties, :StatusStreamID)
    status_stream = Aeron.add_publication(sm.client, status_uri, status_stream_id)

    control_uri = get_property(sm.properties, :ControlURI)
    control_stream_id = get_property(sm.properties, :ControlStreamID)
    control_stream = Aeron.add_subscription(sm.client, control_uri, control_stream_id)
    fragment_handler = Aeron.FragmentHandler(control_handler, sm)

    if is_set(sm.properties, :ControlStreamFilter)
        message_filter = SpidersTagFragmentFilter(fragment_handler, get_property(sm.properties, :ControlStreamFilter))
        control_fragment_handler = Aeron.FragmentAssembler(message_filter)
    else
        control_fragment_handler = Aeron.FragmentAssembler(fragment_handler)
    end

    input_fragment_handler = Aeron.FragmentAssembler(Aeron.FragmentHandler(data_handler, sm))
    input_streams = Vector{Aeron.Subscription}(undef, 0)
    i = 1
    while haskey(ENV, "SUB_DATA_URI_$i")
        uri = ENV["SUB_DATA_URI_$i"]
        stream_id = parse(Int, get(ENV, "SUB_DATA_STREAM_$i") do
            error("Environment variable SUB_DATA_STREAM_$i not found")
        end)
        subscription = Aeron.add_subscription(sm.client, uri, stream_id)
        push!(input_streams, subscription)
        i += 1
    end

    sm.comms = CommunicationResources(
        status_stream,
        control_stream,
        input_streams,
        control_fragment_handler,
        input_fragment_handler,
        Vector{UInt8}(undef, 1 << 23)
    )

end

function teardown_communications!(sm::ControlStateMachine)
    close(sm.comms.status_stream)
    close(sm.comms.control_stream)
    for subscription in sm.comms.input_streams
        close(subscription)
    end
end

@on_event function (sm::ControlStateMachine, ::Top, ::Initialize, _)
    setup_communications!(sm)
    Hsm.transition!(sm, :Top)
end

# @on_event function (sm::ControlStateMachine, ::Top, ::Shutdown, _)
#     teardown_communications!(sm)
#     Hsm.transition!(sm, :Exit)
# end
