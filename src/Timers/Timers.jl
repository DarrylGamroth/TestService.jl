# Timers Module
# Provides event-based timer scheduling functionality

module Timers

using Clocks

export PolledTimer, schedule!, schedule_at!, cancel!, poll, event
export TimerError, TimerNotFoundError, InvalidTimerError, TimerSchedulingError

include("exceptions.jl")
include("polledtimer.jl")

# Precompile statements for PolledTimer
function _precompile()
    # PolledTimer construction
    precompile(Tuple{typeof(PolledTimer),CachedEpochClock{EpochClock}})

    # Timer scheduling functions
    precompile(Tuple{typeof(schedule!),PolledTimer{CachedEpochClock{EpochClock},Symbol},Int64,Symbol})
    precompile(Tuple{typeof(schedule_at!),PolledTimer{CachedEpochClock{EpochClock},Symbol},Int64,Symbol})

    # Timer cancellation functions
    precompile(Tuple{typeof(cancel!),PolledTimer{CachedEpochClock{EpochClock},Symbol},Int64})
    precompile(Tuple{typeof(cancel!),PolledTimer{CachedEpochClock{EpochClock},Symbol},Symbol})
    precompile(Tuple{typeof(cancel!),PolledTimer{CachedEpochClock{EpochClock},Symbol}})

    # Timer polling
    precompile(Tuple{typeof(poll),Function,PolledTimer{CachedEpochClock{EpochClock},Symbol},Any})

    # Timer lookup and accessors
    precompile(Tuple{typeof(event),PolledTimer{CachedEpochClock{EpochClock},Symbol},Int64})
    precompile(Tuple{typeof(Base.length),PolledTimer{CachedEpochClock{EpochClock},Symbol}})
    precompile(Tuple{typeof(Base.isempty),PolledTimer{CachedEpochClock{EpochClock},Symbol}})

    # TimerEntry operations
    precompile(Tuple{typeof(TimerEntry),Int64,Int64,Symbol})
    precompile(Tuple{typeof(Base.isless),TimerEntry{Symbol},TimerEntry{Symbol}})
end

# Call precompile function
_precompile()

end # module Timers
