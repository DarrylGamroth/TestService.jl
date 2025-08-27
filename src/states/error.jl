# Error state handlers
# Handles error state entry and behaviors

@statedef RtcAgent :Error :Top

@on_entry function (sm::RtcAgent, ::Error)
    @info "Error"
end
