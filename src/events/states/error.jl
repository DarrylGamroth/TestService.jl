# Error state handlers
# Handles error state entry and behaviors

@statedef EventManager :Error :Top

@on_entry function (sm::EventManager, ::Error)
    @info "Error"
end
