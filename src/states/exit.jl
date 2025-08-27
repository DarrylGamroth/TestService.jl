# Exit state handlers
# Handles graceful shutdown and termination

@statedef RtcAgent :Exit :Top

@on_entry function (sm::RtcAgent, state::Exit)
    @info "Entering state: $(state)"
    throw(AgentTerminationException())
end
