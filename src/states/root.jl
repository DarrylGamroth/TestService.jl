# Root state handlers
# Handles default property operations and common state behaviors

# Root state is implicitly defined by the HSM framework

@on_event function (sm::RtcAgent, state::Root, event::Any, message::EventMessage)
    @info "Default handler called with event: $(event)"
    if event in keynames(sm.properties)
        if SpidersMessageCodecs.format(message) == SpidersMessageCodecs.Format.NOTHING
            # If the message has no value, then it is a request for the current value
            handle_property_read(sm, event, message)
        else
            # Otherwise it's a write request
            handle_property_write(sm, event, message)
        end
        return Hsm.EventHandled
    end

    # Defer to the ancestor handler
    return Hsm.EventNotHandled
end

# These are useful for debugging but prevent the module from precompilation
# @on_entry function (sm::RtcAgent, state::Any)
#     @info "Entering state: $(state)"
# end

# @on_exit function (sm::RtcAgent, state::Any)
#     @info "Exiting state: $(state)"
# end

@on_initial function (sm::RtcAgent, ::Root)
    Hsm.transition!(sm, :Top)
end
