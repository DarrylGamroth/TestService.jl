# Timer System Module
# Handles timer wheel management, timer scheduling, and timer event mapping

module TimerSystem

using Clocks
using TimerWheels

export TimerManager,
    schedule_timer_at!,
    schedule_timer_in!,
    cancel_timer!,
    poll_timers!,
    timer_poller

"""
Timer management system that encapsulates timer wheel and event mapping.
"""
mutable struct TimerManager{C<: Clocks.AbstractClock}
    clock::C
    wheel::DeadlineTimerWheel
    event_map::Dict{Int64,Symbol}

    function TimerManager(clock::C, wheel_size::Int=(1 << 21), tick_size::Int=(1 << 9)) where {C<: Clocks.AbstractClock}
        initial_time = time_nanos(clock)
        timer_wheel = DeadlineTimerWheel(initial_time, wheel_size, tick_size)
        event_map = Dict{Int64,Symbol}()
        sizehint!(event_map, 100)  # Preallocate for performance

        new{C}(clock, timer_wheel, event_map)
    end
end

"""
    schedule_timer_at!(tm::TimerManager, deadline::Int64, event::Symbol) -> Int64

Schedule a timer to fire at the given absolute deadline with the associated event.
Returns the timer ID for potential cancellation.
"""
function schedule_timer_at!(tm::TimerManager, deadline::Int64, event::Symbol)
    timer_id = TimerWheels.schedule_timer!(tm.wheel, deadline)
    tm.event_map[timer_id] = event
    return timer_id
end

"""
    cancel_timer!(tm::TimerManager, timer_id::Int64) -> Bool

Cancel a scheduled timer. Returns true if the timer was found and cancelled.
"""
function cancel_timer!(tm::TimerManager, timer_id::Int64)
    # Remove from event mapping
    deleted = delete!(tm.event_map, timer_id)

    # Cancel in timer wheel
    cancelled = TimerWheels.cancel_timer(tm.wheel, timer_id)

    return deleted !== nothing && cancelled
end

"""
    poll_timers!(handler, tm::TimerManager, now::Int64, context) -> Int

Poll the timer wheel for expired timers and call handler_func for each one.
Returns the number of timers that fired.
"""
function poll_timers!(handler, tm::TimerManager, now::Int64, context)
    return TimerWheels.poll(handler, tm.wheel, now, context)
end

"""
    get_timer_event(tm::TimerManager, timer_id::Int64) -> Symbol

Get the event associated with a timer ID, removing it from the mapping.
Returns :DefaultTimer if the timer ID is not found.
"""
function get_timer_event(tm::TimerManager, timer_id::Int64)
    event = get(tm.event_map, timer_id, :DefaultTimer)
    delete!(tm.event_map, timer_id)
    return event
end

"""
    schedule_timer_in!(tm::TimerManager, event::Symbol, delay_ns::Int64) -> Int64

Schedule a timer event with a relative delay from now.
Returns the timer ID for potential cancellation.
"""
function schedule_timer_in!(tm::TimerManager, event::Symbol, delay_ns::Int64)
    # Calculate absolute deadline from current time + delay
    now = time_nanos(tm.clock)
    deadline = now + delay_ns
    return schedule_timer_at!(tm, deadline, event)
end

"""
    cancel_timer_by_event!(tm::TimerManager, event::Symbol) -> Int

Cancel all timers associated with a specific event.
Returns the number of timers cancelled.
"""
function cancel_timer_by_event!(tm::TimerManager, event::Symbol)
    cancelled_count = 0

    # Find all timer IDs associated with this event
    timer_ids_to_cancel = Int64[]
    for (timer_id, mapped_event) in tm.event_map
        if mapped_event == event
            push!(timer_ids_to_cancel, timer_id)
        end
    end

    # Cancel each timer
    for timer_id in timer_ids_to_cancel
        if cancel_timer!(tm, timer_id)
            cancelled_count += 1
        end
    end

    return cancelled_count
end

"""
    cancel_all_timers!(tm::TimerManager) -> Int

Cancel all active timers.
Returns the number of timers cancelled.
"""
function cancel_all_timers!(tm::TimerManager)
    cancelled_count = 0

    # Get all active timer IDs
    timer_ids = collect(keys(tm.event_map))

    # Cancel each one
    for timer_id in timer_ids
        if cancel_timer!(tm, timer_id)
            cancelled_count += 1
        end
    end

    return cancelled_count
end

"""
    timer_poller(handler, tm::TimerManager, context) -> Int

Poll the timer wheel for expired timers and call handler for each one.
Returns the number of timers that fired.
"""
function timer_poller(handler, tm::TimerManager, context)
    # Poll the timer wheel for any expired timers
    now = time_nanos(tm.clock)
    return poll_timers!(handler, tm, now, context)
end

# Precompile statements for TimerSystem
function _precompile()
    # TimerManager construction
    precompile(Tuple{typeof(TimerManager),CachedEpochClock{EpochClock}})

    # Timer scheduling functions
    precompile(Tuple{typeof(schedule_timer_in!),TimerManager{CachedEpochClock{EpochClock}},Symbol,Int64})
    precompile(Tuple{typeof(schedule_timer_at!),TimerManager{CachedEpochClock{EpochClock}},Int64,Symbol})

    # Timer cancellation functions
    precompile(Tuple{typeof(cancel_timer!),TimerManager{CachedEpochClock{EpochClock}},Int64})
    precompile(Tuple{typeof(cancel_timer_by_event!),TimerManager{CachedEpochClock{EpochClock}},Symbol})
    precompile(Tuple{typeof(cancel_all_timers!),TimerManager{CachedEpochClock{EpochClock}}})

    # Timer polling
    precompile(Tuple{typeof(timer_poller),Function,TimerManager{CachedEpochClock{EpochClock}},Any})
    precompile(Tuple{typeof(poll_timers!),TimerManager{CachedEpochClock{EpochClock}},Int64,Any})
end

# Call precompile function
_precompile()

end # module TimerSystem
