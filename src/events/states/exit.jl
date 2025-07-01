# Exit state handlers
# Handles graceful shutdown and termination

@statedef EventManager :Exit :Top

@on_entry function (sm::EventManager, state::Exit)
    @info "Entering state: $(state)"
    throw(AgentTerminationException())
end
