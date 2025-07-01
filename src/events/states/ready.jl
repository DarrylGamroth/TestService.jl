# Ready state handlers
# Handles communication setup/teardown and initial transitions

@statedef EventManager :Ready :Top

@on_initial function (sm::EventManager, ::Ready)
    Hsm.transition!(sm, :Stopped)
end

@on_event function (sm::EventManager, ::Ready, ::Reset, _)
    Hsm.transition!(sm, :Ready)
end
