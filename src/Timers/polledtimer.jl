"""
    TimerEntry{E}

Entry in the timer queue with deadline, ID, and associated event.

Contains deadline for ordering, unique ID for cancellation, and event payload.
"""
struct TimerEntry{E}
    deadline::Int64
    id::Int64
    event::E
end

# Custom comparison for reverse sorting (latest deadline first) without allocations
Base.isless(a::TimerEntry, b::TimerEntry) = a.deadline > b.deadline

"""
    PolledTimer{C,E}

Zero-allocation timer scheduler using a sorted vector for efficient polling.

Maintains timers in deadline order for O(1) next-timer queries. Uses reverse
sorting (latest first) to optimize common polling patterns.

# Type Parameters
- `C<:Clocks.AbstractClock`: clock implementation for timing operations
- `E`: event type stored with timer entries (typically Symbol)

# Fields
- `clock::C`: timing source for deadline calculations
- `timers::Vector{TimerEntry{E}}`: sorted timer queue (reverse deadline order)
- `next_id::Int64`: incrementing ID generator for timer identification
"""
mutable struct PolledTimer{C<:Clocks.AbstractClock,E}
    clock::C
    timers::Vector{TimerEntry{E}}
    next_id::Int64

    function PolledTimer{C,E}(clock::C) where {C<:Clocks.AbstractClock,E}
        timers = TimerEntry{E}[]
        @static if VERSION >= v"1.11"
            sizehint!(timers, 100; shrink=false)
        else
            sizehint!(timers, 100)
        end
        new{C,E}(clock, timers, 1)
    end
end

# Convenience constructor for Symbol events (most common case)
PolledTimer(clock::C) where C<:Clocks.AbstractClock = PolledTimer{C, Symbol}(clock)

"""
    schedule!(timer::PolledTimer, delay_ns::Int64, event) -> Int64

Schedule a timer event with a relative delay from now.
Returns the timer ID for potential cancellation.
"""
function schedule!(timer::PolledTimer, delay_ns::Int64, event)
    if delay_ns < 0
        throw(InvalidTimerError("Timer delay cannot be negative: $(delay_ns)"))
    end
    
    now = time_nanos(timer.clock)
    return schedule_at!(timer, now + delay_ns, event)
end

"""
    schedule_at!(timer::PolledTimer, deadline::Int64, event) -> Int64

Schedule a timer to fire at the given absolute deadline with the associated event.
Returns the timer ID for potential cancellation.
"""
function schedule_at!(timer::PolledTimer, deadline::Int64, event)
    now = time_nanos(timer.clock)
    if deadline < now
        throw(TimerSchedulingError("Cannot schedule timer in the past", deadline))
    end
    
    timer_id = timer.next_id
    timer.next_id += 1

    entry = TimerEntry(deadline, timer_id, event)

    # Insert in reverse sorted order using custom isless (zero allocations)
    insert_index = searchsortedfirst(timer.timers, entry)
    insert!(timer.timers, insert_index, entry)

    return timer_id
end

"""
    cancel!(timer::PolledTimer, timer_id::Int64) -> Bool

Cancel a scheduled timer. Returns true if the timer was found and cancelled.
"""
function cancel!(timer::PolledTimer, timer_id::Int64)
    index = findfirst(t -> t.id == timer_id, timer.timers)
    if index !== nothing
        deleteat!(timer.timers, index)
        return true
    end
    return false
end

"""
    cancel!(timer::PolledTimer, event) -> Int

Cancel all timers associated with a specific event.
Returns the number of timers cancelled.
"""
function cancel!(timer::PolledTimer, event)
    len = length(timer.timers)
    filter!(t -> t.event != event, timer.timers)
    return len - length(timer.timers)
end

"""
    cancel!(timer::PolledTimer) -> Int

Cancel all active timers.
Returns the number of timers cancelled.
"""
function cancel!(timer::PolledTimer)
    cancelled_count = length(timer.timers)
    empty!(timer.timers)
    return cancelled_count
end

"""
    poll(handler, timer::PolledTimer, clientd) -> Int

Poll for expired timers and call handler for each one.
Returns the number of timers that fired.
"""
@inline function poll(handler, timer::PolledTimer, clientd)
    now = time_nanos(timer.clock)
    fired_count = 0

    # Process expired timers from the end of the reverse-sorted vector
    while !isempty(timer.timers) && timer.timers[end].deadline <= now
        expired_timer = pop!(timer.timers)
        handler(expired_timer.event, now, clientd)
        fired_count += 1
    end

    return fired_count
end

"""
    event(timer::PolledTimer, timer_id::Int64)

Get the event associated with a timer ID.
Returns `nothing` if the timer ID is not found.
"""
function event(timer::PolledTimer, timer_id::Int64)
    for t in timer.timers
        if t.id == timer_id
            return t.event
        end
    end
    return nothing
end

"""
    length(timer::PolledTimer) -> Int

Get the number of active timers.
"""
Base.length(timer::PolledTimer) = length(timer.timers)

"""
    isempty(timer::PolledTimer) -> Bool

Check if there are any active timers.
"""
Base.isempty(timer::PolledTimer) = isempty(timer.timers)
