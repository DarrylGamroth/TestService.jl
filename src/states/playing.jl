# Playing state handlers
# Handles events specific to the playing state

@statedef RtcAgent :Playing :Processing

@on_event function (sm::RtcAgent, ::Playing, ::Pause, _)
    Hsm.transition!(sm, :Paused)
end

@on_entry function (sm::RtcAgent, ::Playing)
    register!(sm, :TestMatrix, 1, Periodic(1_000_000_000))
    nothing
end

@on_exit function (sm::RtcAgent, ::Playing)
    unregister!(sm, :TestMatrix)
    nothing
end
