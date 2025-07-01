# Publication Strategy System
# 
# This module provides publication strategies that determine when and how
# properties should be published based on timing and update patterns.

# Individual strategy types
struct OnUpdateStrategy end

struct PeriodicStrategy
    interval_ns::Int64
end

struct ScheduledStrategy
    schedule_ns::Int64
end

struct RateLimitedStrategy
    min_interval_ns::Int64
end

# LightSumTypes-based strategy union for type-stable dispatch
@sumtype PublishStrategy(
    OnUpdateStrategy,
    PeriodicStrategy,
    ScheduledStrategy,
    RateLimitedStrategy
)

# Convenient constructor functions that return the PublishStrategy sum type
"""
    OnUpdate()

Create an OnUpdate strategy that publishes whenever a property is updated.
Returns a PublishStrategy sum type for type-stable dispatch.
"""
OnUpdate() = PublishStrategy(OnUpdateStrategy())

"""
    Periodic(interval_ns::Int64)

Create a Periodic strategy that publishes at regular intervals.
Returns a PublishStrategy sum type for type-stable dispatch.
"""
Periodic(interval_ns::Int64) = PublishStrategy(PeriodicStrategy(interval_ns))

"""
    Scheduled(schedule_ns::Int64)

Create a Scheduled strategy that publishes at a specific scheduled time.
Returns a PublishStrategy sum type for type-stable dispatch.
"""
Scheduled(schedule_ns::Int64) = PublishStrategy(ScheduledStrategy(schedule_ns))

"""
    RateLimited(min_interval_ns::Int64)

Create a RateLimited strategy that publishes on updates but enforces a minimum interval.
Returns a PublishStrategy sum type for type-stable dispatch.
"""
RateLimited(min_interval_ns::Int64) = PublishStrategy(RateLimitedStrategy(min_interval_ns))

# Publishing strategy logic using type-stable dispatch through LightSumTypes
"""
    should_publish(strategy::PublishStrategy, last_published_ns::Int64, next_scheduled_ns::Int64, property_timestamp_ns::Int64, current_time_ns::Int64)

Determine whether a property should be published based on the strategy and timing.
These functions are optimized for type stability and minimal allocations using LightSumTypes.
"""
@inline function should_publish(strategy::PublishStrategy,
    last_published_ns::Int64,
    next_scheduled_ns::Int64,
    property_timestamp_ns::Int64,
    current_time_ns::Int64)
    
    # Use LightSumTypes variant for type-stable dispatch
    concrete_strategy = variant(strategy)
    return should_publish(concrete_strategy, last_published_ns, next_scheduled_ns, property_timestamp_ns, current_time_ns)
end

# Multiple dispatch implementations for each strategy type
@inline function should_publish(::OnUpdateStrategy,
    ::Int64,
    ::Int64,
    property_timestamp_ns::Int64,
    current_time_ns::Int64)
    # Publish if the property was updated in the current loop (timestamp matches current time)
    return property_timestamp_ns == current_time_ns
end

@inline function should_publish(strategy::PeriodicStrategy,
    last_published_ns::Int64,
    ::Int64,
    ::Int64,
    current_time_ns::Int64)
    if last_published_ns < 0
        return true  # First publication
    end
    return (current_time_ns - last_published_ns) >= strategy.interval_ns
end

@inline function should_publish(::ScheduledStrategy,
    ::Int64,
    next_scheduled_ns::Int64,
    ::Int64,
    current_time_ns::Int64)
    return current_time_ns >= next_scheduled_ns
end

@inline function should_publish(strategy::RateLimitedStrategy,
    last_published_ns::Int64,
    ::Int64,
    property_timestamp_ns::Int64,
    current_time_ns::Int64)
    # Only consider publishing if the property was updated in this loop
    if property_timestamp_ns != current_time_ns
        return false
    end

    if last_published_ns < 0
        return true  # First publication
    end

    return (current_time_ns - last_published_ns) >= strategy.min_interval_ns
end

# Next scheduled time calculation
"""
    next_time(strategy::PublishStrategy, current_time_ns::Int64)

Calculate the next scheduled publication time for strategies that need it.
These functions are optimized for type stability using LightSumTypes.
"""
@inline function next_time(strategy::PublishStrategy, current_time_ns::Int64)
    # Use LightSumTypes variant for type-stable dispatch
    concrete_strategy = variant(strategy)
    return next_time(concrete_strategy, current_time_ns)
end

# Multiple dispatch implementations for each strategy type
@inline function next_time(::OnUpdateStrategy, ::Int64)
    return -1  # OnUpdate doesn't schedule
end

@inline function next_time(strategy::PeriodicStrategy, current_time_ns::Int64)
    return current_time_ns + strategy.interval_ns
end

@inline function next_time(strategy::ScheduledStrategy, ::Int64)
    return strategy.schedule_ns
end

@inline function next_time(strategy::RateLimitedStrategy, current_time_ns::Int64)
    return current_time_ns + strategy.min_interval_ns
end
