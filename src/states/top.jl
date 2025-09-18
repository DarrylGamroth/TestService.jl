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
    publish_event_response(sm, event, Hsm.current(sm))

    # Reschedule the next heartbeat
    next_heartbeat_time = now + sm.properties[:HeartbeatPeriodNs]
    schedule_at!(sm.timers, next_heartbeat_time, :Heartbeat)

    return Hsm.EventHandled
end

@on_event function (sm::RtcAgent, ::Top, event::Error, (e, exception))
    publish_event_response(sm, event, exception)
    @error "Error in dispatching event $e" exception
    return Hsm.EventHandled

    # Transition to Error state
    # Hsm.transition!(sm, :Error)
end

@on_event function (sm::RtcAgent, ::Top, ::AgentOnClose, _)
    Hsm.transition!(sm, :Exit)
end

@on_event function (sm::RtcAgent, ::Top, event::State, _)
    publish_event_response(sm, event, Hsm.current(sm))
    return Hsm.EventHandled
end

@on_event function (sm::RtcAgent, ::Top, ::GC, _)
    GC.gc()
    return Hsm.EventHandled
end

@on_event function (sm::RtcAgent, ::Top, ::Exit, _)
    Hsm.transition!(sm, :Exit)
end

@on_event function (sm::RtcAgent, ::Top, event::LateMessage, _)
    publish_event_response(sm, event, nothing)    
    return Hsm.EventHandled
end

@on_event function (sm::RtcAgent, ::Top, ::Properties, message)
    for name in keynames(sm.properties)
        on_property_read(sm, name, message)
    end
    return Hsm.EventHandled
end
