# Ready state handlers
# Handles communication setup/teardown and initial transitions

@statedef RtcAgent :Ready :Top

@on_initial function (sm::RtcAgent, ::Ready)
    Hsm.transition!(sm, :Stopped)
end

@on_event function (sm::RtcAgent, ::Ready, ::Reset, _)
    Hsm.transition!(sm, :Ready)
end
