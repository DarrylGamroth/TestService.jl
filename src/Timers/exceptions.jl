# Timer-specific exceptions
# Provides domain-specific error types for timer operations

"""
    TimerError

Base type for all timer-related errors.
"""
abstract type TimerError <: Exception end

"""
    TimerNotFoundError(timer_id::Int64)

Thrown when attempting to operate on a timer that doesn't exist.
"""
struct TimerNotFoundError <: TimerError
    timer_id::Int64
end

function Base.showerror(io::IO, e::TimerNotFoundError)
    print(io, "TimerNotFoundError: Timer with ID $(e.timer_id) not found")
end

"""
    InvalidTimerError(message::String)

Thrown when timer operation parameters are invalid.
"""
struct InvalidTimerError <: TimerError
    message::String
end

function Base.showerror(io::IO, e::InvalidTimerError)
    print(io, "InvalidTimerError: $(e.message)")
end

"""
    TimerSchedulingError(message::String, deadline::Int64)

Thrown when timer scheduling fails due to invalid timing.
"""
struct TimerSchedulingError <: TimerError
    message::String
    deadline::Int64
end

function Base.showerror(io::IO, e::TimerSchedulingError)
    print(io, "TimerSchedulingError: $(e.message) (deadline: $(e.deadline))")
end
