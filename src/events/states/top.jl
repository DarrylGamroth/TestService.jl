# Top state handlers
# Handles top-level events like heartbeat, reset, errors, and system commands

@statedef EventManager :Top

@on_entry function (sm::EventManager, state::Top)
    @info "Entering state: $(state)"
    # Communication setup is handled by the RtcAgent coordinator
    # No need to set up communications here anymore
    
    schedule_timer_event!(sm, :Heartbeat, 0)
end

@on_exit function (sm::EventManager, state::Top)
    @info "Exiting state: $(state)"

    cancel_all_timers!(sm)
    # Communication teardown is handled by the RtcAgent coordinator  
    # No need to tear down communications here anymore
end

@on_initial function (sm::EventManager, ::Top)
    Hsm.transition!(sm, :Ready)
end

@on_event function (sm::EventManager, ::Top, event::Heartbeat, now::Int64)
    # Generate a new correlation ID for the heartbeat event
    sm.correlation_id = next_id(sm.id_gen)

    # Handle heartbeat timeout by sending a heartbeat event
    send_event_response(sm, event, Hsm.current(sm))

    # Reschedule the next heartbeat using absolute time API
    next_heartbeat_time = now + sm.properties[:HeartbeatPeriodNs]
    schedule_timer_event_at!(sm, :Heartbeat, next_heartbeat_time)

    return Hsm.EventHandled
end

@on_event function (sm::EventManager, ::Top, event::Error, error::Exception)
    send_event_response(sm, event, "$error")
    return Hsm.EventHandled

    # Transition to Error state
    # Hsm.transition!(sm, :Error)
end

@on_event function (sm::EventManager, ::Top, ::AgentOnClose, _)
    Hsm.transition!(sm, :Exit)
end

@on_event function (sm::EventManager, ::Top, ::State, _)
    send_event_response(sm, :State, Hsm.current(sm))
    return Hsm.EventHandled
end

@on_event function (sm::EventManager, ::Top, ::GC, _)
    GC.gc()
    return Hsm.EventHandled
end

@on_event function (sm::EventManager, ::Top, ::Exit, _)
    Hsm.transition!(sm, :Exit)
end

@on_event function (sm::EventManager, ::Top, ::Properties, message)
    properties = sm.properties
    for name in property_names(properties)
        handle_property_read(sm, properties, name, message)
    end
    return Hsm.EventHandled
end

# Property publication event handlers
# @on_event function (sm::EventManager, ::Top, ::RegisterPropertyPublication, message)
#     PropertiesSystem.handle_register_publication_event(sm, message)
#     return Hsm.EventHandled
# end

# @on_event function (sm::EventManager, ::Top, ::UnregisterPropertyPublication, message)
#     PropertiesSystem.handle_unregister_publication_event(sm, message)
#     return Hsm.EventHandled
# end

# @on_event function (sm::EventManager, ::Top, ::ListPropertyPublications, _)
#     publications = PropertiesSystem.list()
#     send_event_response(sm, :PropertyPublications, publications)
#     return Hsm.EventHandled
# end
