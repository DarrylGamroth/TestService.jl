# Paused state handlers
# Handles events specific to the paused state

@statedef EventManager :Paused :Processing

@on_event function (sm::EventManager, ::Paused, ::Play, _)
    Hsm.transition!(sm, :Playing)
end
