# Timer API functions for ControlStateMachine
# Provides high-level timer scheduling and management with event mapping

# Schedule a timer event with a relative delay from now
function schedule_timer_event!(sm::ControlStateMachine, event::Symbol, delay_ns::Int64)
    # Calculate absolute deadline from current time + delay
    now = time_nanos(sm.clock)
    deadline = now + delay_ns
    timer_id = schedule_timer!(sm.timer_wheel, deadline)
    
    # This won't allocate if capacity is sufficient
    sm.timer_event_map[timer_id] = event
    
    return timer_id
end

# Schedule a timer event at an absolute deadline
function schedule_timer_event_at!(sm::ControlStateMachine, event::Symbol, deadline_ns::Int64)
    # Schedule timer at absolute deadline
    timer_id = schedule_timer!(sm.timer_wheel, deadline_ns)
    
    # This won't allocate if capacity is sufficient
    sm.timer_event_map[timer_id] = event
    
    return timer_id
end

# Cancel a specific timer by its ID
function cancel_timer!(sm::ControlStateMachine, timer_id::Int64)
    # Cancel the timer in the timer wheel
    cancelled = TimerWheels.cancel!(sm.timer_wheel, timer_id)
    
    # Clean up the event mapping if it exists
    if haskey(sm.timer_event_map, timer_id)
        delete!(sm.timer_event_map, timer_id)
    end
    
    return cancelled
end

# Cancel all timers associated with a specific event
function cancel_timer_by_event!(sm::ControlStateMachine, event::Symbol)
    cancelled_count = 0
    
    # Find all timer IDs associated with this event
    timer_ids_to_cancel = Int64[]
    for (timer_id, mapped_event) in sm.timer_event_map
        if mapped_event == event
            push!(timer_ids_to_cancel, timer_id)
        end
    end
    
    # Cancel each timer
    for timer_id in timer_ids_to_cancel
        if cancel_timer!(sm, timer_id)
            cancelled_count += 1
        end
    end
    
    return cancelled_count
end

# Cancel all active timers
function cancel_all_timers!(sm::ControlStateMachine)
    cancelled_count = 0
    
    # Get all active timer IDs
    timer_ids = collect(keys(sm.timer_event_map))
    
    # Cancel each one
    for timer_id in timer_ids
        if cancel_timer!(sm, timer_id)
            cancelled_count += 1
        end
    end
    
    return cancelled_count
end

# Precompile timer API functions for performance
function precompile_timers()
    precompile(Tuple{typeof(schedule_timer_event!),ControlStateMachine,Symbol,Int64})
    precompile(Tuple{typeof(schedule_timer_event_at!),ControlStateMachine,Symbol,Int64})
    precompile(Tuple{typeof(cancel_timer!),ControlStateMachine,Int64})
    precompile(Tuple{typeof(cancel_timer_by_event!),ControlStateMachine,Symbol})
    precompile(Tuple{typeof(cancel_all_timers!),ControlStateMachine})
end
