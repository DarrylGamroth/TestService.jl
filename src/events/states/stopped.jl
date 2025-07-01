# Stopped state handlers
# Handles transitions from stopped to playing state

@statedef EventManager :Stopped :Ready

@on_event function (sm::EventManager, ::Stopped, ::Play, _)
    # Only transition if all properties are set
    if all_properties_set(sm.properties)
        return Hsm.transition!(sm, :Playing)
    end

    return Hsm.EventHandled
end
