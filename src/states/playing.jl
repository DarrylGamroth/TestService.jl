# Playing state handlers
# Handles events specific to the playing state

@statedef RtcAgent :Playing :Processing

@on_event function (sm::RtcAgent, ::Playing, ::Pause, _)
    Hsm.transition!(sm, :Paused)
end

# @on_entry function (sm::RtcAgent, ::Playing)
#     schedule!(sm.timers, 0, :DataEvent)
#     nothing
# end

# @on_exit function (sm::RtcAgent, ::Playing)
#     cancel!(sm.timers, :DataEvent)
#     nothing
# end

# @on_event function (sm::RtcAgent, ::Playing, ::DataEvent, now)
#     next_data_event = now + 1_000_000_000
#     schedule_at!(sm.timers, next_data_event, :DataEvent)

#     # Update property - this should automatically set the timestamp to current loop time
#     sm.properties[:TestMatrix] = rand(Float32, 10, 5, 2)  # Example of updating the property
#     # The timestamp will be set automatically by the Properties system
#     # This enables the publication system to detect the update

#     return Hsm.EventHandled
# end

@on_entry function (sm::RtcAgent, ::Playing)
    register!(sm, :TestMatrix, 1, Periodic(1_000_000_000))
    nothing
end

@on_exit function (sm::RtcAgent, ::Playing)
    unregister!(sm, :TestMatrix)
    nothing
end
