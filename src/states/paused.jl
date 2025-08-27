# Paused state handlers
# Handles events specific to the paused state

@statedef RtcAgent :Paused :Processing

@on_event function (sm::RtcAgent, ::Paused, ::Play, _)
    Hsm.transition!(sm, :Playing)
end
