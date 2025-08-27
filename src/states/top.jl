# Top state handlers
# Handles top-level events like heartbeat, reset, errors, and system commands

@statedef RtcAgent :Top

@on_entry function (sm::RtcAgent, state::Top)
    @info "Entering state: $(state)"

    schedule!(sm.timers, 0, :Heartbeat)
end

@on_exit function (sm::RtcAgent, state::Top)
    @info "Exiting state: $(state)"

    cancel!(sm.timers)
end

@on_initial function (sm::RtcAgent, ::Top)
    Hsm.transition!(sm, :Ready)
end

@on_event function (sm::RtcAgent, ::Top, event::Heartbeat, now::Int64)
    sm.correlation_id = next_id(sm.id_gen)

    # Send current state as the Heartbeat message
    send_event_response(sm, event, Hsm.current(sm))

    # Reschedule the next heartbeat
    next_heartbeat_time = now + sm.properties[:HeartbeatPeriodNs]
    schedule_at!(sm.timers, next_heartbeat_time, :Heartbeat)

    return Hsm.EventHandled
end

@on_event function (sm::RtcAgent, ::Top, event::Error, error::Exception)
    send_event_response(sm, event, "$error")
    return Hsm.EventHandled

    # Transition to Error state
    # Hsm.transition!(sm, :Error)
end

@on_event function (sm::RtcAgent, ::Top, ::AgentOnClose, _)
    Hsm.transition!(sm, :Exit)
end

@on_event function (sm::RtcAgent, ::Top, ::State, _)
    send_event_response(sm, :State, Hsm.current(sm))
    return Hsm.EventHandled
end

@on_event function (sm::RtcAgent, ::Top, ::GC, _)
    GC.gc()
    return Hsm.EventHandled
end

@on_event function (sm::RtcAgent, ::Top, ::Exit, _)
    Hsm.transition!(sm, :Exit)
end

@on_event function (sm::RtcAgent, ::Top, ::Properties, message)
    properties = sm.properties
    for name in keynames(properties)
        handle_property_read(sm, properties, name, message)
    end
    return Hsm.EventHandled
end
