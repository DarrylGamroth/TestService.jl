# Root state handlers
# Handles default property operations and common state behaviors

# Root state is implicitly defined by the HSM framework

@on_event function (sm::EventManager, state::Root, event::Any, message::EventMessage)
    @info "Default handler called with event: $(event)"
    properties = sm.properties
    if event in property_names(properties)
        if SpidersMessageCodecs.format(message) == SpidersMessageCodecs.Format.NOTHING
            # If the message has no value, then it is a request for the current value
            handle_property_read(sm, properties, event, message)
        else
            # Otherwise it's a write request
            handle_property_write(sm, properties, event, message)
        end
        return Hsm.EventHandled
    end

    # Defer to the ancestor handler
    return Hsm.EventNotHandled
end

@on_entry function (sm::EventManager, state::Any)
    @info "Entering state: $(state)"
end

@on_exit function (sm::EventManager, state::Any)
    @info "Exiting state: $(state)"
end

@on_initial function (sm::EventManager, ::Root)
    Hsm.transition!(sm, :Top)
end
