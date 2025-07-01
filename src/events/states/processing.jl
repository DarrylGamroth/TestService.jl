# Processing state handlers
# Handles common processing state behaviors and transitions

@statedef EventManager :Processing :Ready

@on_initial function (sm::EventManager, ::Processing)
    Hsm.transition!(sm, :Paused)
end

@on_event function (sm::EventManager, ::Processing, ::Stop, _)
    Hsm.transition!(sm, :Stopped)
end
