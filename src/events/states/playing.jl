# Playing state handlers
# Handles events specific to the playing state

@statedef EventManager :Playing :Processing

@on_event function (sm::EventManager, ::Playing, ::Pause, _)
    Hsm.transition!(sm, :Paused)
end

@on_entry function (sm::EventManager, ::Playing)
    # Schedule the first :DataEvent
    schedule_timer_event!(sm, :DataEvent, 0)
end

@on_exit function (sm::EventManager, ::Playing)
    # Cancel :DataEvent when exiting Playing state
    cancel_timer_by_event!(sm, :DataEvent)
end

@on_event function (sm::EventManager, ::Playing, ::DataEvent, message)
    now = message  # message contains the current timestamp from timer
    next_data_event = now + 1_000_000_000
    schedule_timer_event_at!(sm, :DataEvent, next_data_event)

    # Update property - this should automatically set the timestamp to current loop time
    sm.properties[:TestMatrix] = rand(Float32, 10, 5, 2)  # Example of updating the property
    # The timestamp will be set automatically by the Properties system
    # This enables the publication system to detect the update

    return Hsm.EventHandled
end
