# Processing state handlers
# Handles common processing state behaviors and transitions

@statedef RtcAgent :Processing :Ready

@on_entry function (sm::RtcAgent, ::Processing)
    GC.gc()  # Perform garbage collection on entering processing state
end

@on_initial function (sm::RtcAgent, ::Processing)
    Hsm.transition!(sm, :Paused)
end

@on_event function (sm::RtcAgent, ::Processing, ::Stop, _)
    Hsm.transition!(sm, :Stopped)
end
