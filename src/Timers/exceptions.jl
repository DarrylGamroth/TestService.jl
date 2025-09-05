"""
    TimerError

Base type for all timer-related errors.
"""
abstract type TimerError <: Exception end

"""
    TimerNotFoundError

Thrown when attempting to operate on a timer that doesn't exist.
"""
struct TimerNotFoundError <: TimerError
    timer_id::Int64
end

function Base.showerror(io::IO, e::TimerNotFoundError)
    print(io, "TimerNotFoundError: Timer with ID $(e.timer_id) not found")
end

"""
    InvalidTimerError

Thrown when timer operation parameters are invalid.
"""
struct InvalidTimerError <: TimerError
    message::String
end

function Base.showerror(io::IO, e::InvalidTimerError)
    print(io, "InvalidTimerError: $(e.message)")
end

"""
    TimerSchedulingError

Thrown when timer scheduling fails due to invalid timing.

Contains error message and the problematic deadline for debugging.
"""
struct TimerSchedulingError <: TimerError
    message::String
    deadline::Int64
end

function Base.showerror(io::IO, e::TimerSchedulingError)
    print(io, "TimerSchedulingError: $(e.message) (deadline: $(e.deadline))")
end
