# Precompile statements for TestService.jl
# This file contains precompile directives for hot path functions and critical types
# to reduce first-time execution latency and improve runtime performance.

# Note: This file should be included after rtcagent.jl defines all the types
function _precompile_testservice()
    # Core concrete types used throughout the system
    ClockType = CachedEpochClock{EpochClock}
    PropertiesType = Properties{ClockType}
    IdGenType = SnowflakeIdGenerator{ClockType}
    TimerType = PolledTimer{ClockType,Symbol}
    AgentType = RtcAgent{ClockType,PropertiesType,IdGenType,TimerType}

    # =============================================================================
    # Core Type Construction
    # =============================================================================

    # RtcAgent construction - updated for dependency injection
    precompile(Tuple{typeof(RtcAgent),CommunicationResources,PropertiesType,ClockType})
    precompile(Tuple{typeof(RtcAgent),CommunicationResources,PropertiesType})

    # Properties construction and access
    precompile(Tuple{typeof(Properties),ClockType})
    precompile(Tuple{typeof(getindex),PropertiesType,Symbol})
    precompile(Tuple{typeof(setindex!),PropertiesType,String,Symbol})
    precompile(Tuple{typeof(setindex!),PropertiesType,Int64,Symbol})
    precompile(Tuple{typeof(setindex!),PropertiesType,Float64,Symbol})
    precompile(Tuple{typeof(setindex!),PropertiesType,Bool,Symbol})
    precompile(Tuple{typeof(isset),PropertiesType,Symbol})
    precompile(Tuple{typeof(last_update),PropertiesType,Symbol})

    # PublicationConfig and strategy types
    precompile(Tuple{typeof(PublicationConfig),Symbol,Aeron.ExclusivePublication,Int,PublishStrategy,Int64,Int64})
    precompile(Tuple{typeof(OnUpdate)})
    precompile(Tuple{typeof(Periodic),Int64})
    precompile(Tuple{typeof(Scheduled),Int64})
    precompile(Tuple{typeof(RateLimited),Int64})

    # =============================================================================
    # Hot Path Functions - Property Publishing
    # =============================================================================

    # Property publication - critical hot path
    precompile(Tuple{typeof(publish_property_update),AgentType,PublicationConfig})
    precompile(Tuple{typeof(property_poller),AgentType})

    # Strategy functions - called in every publication evaluation
    precompile(Tuple{typeof(should_publish),PublishStrategy,Int64,Int64,Int64,Int64})
    precompile(Tuple{typeof(should_publish),OnUpdateStrategy,Int64,Int64,Int64,Int64})
    precompile(Tuple{typeof(should_publish),PeriodicStrategy,Int64,Int64,Int64,Int64})
    precompile(Tuple{typeof(should_publish),ScheduledStrategy,Int64,Int64,Int64,Int64})
    precompile(Tuple{typeof(should_publish),RateLimitedStrategy,Int64,Int64,Int64,Int64})

    precompile(Tuple{typeof(next_time),PublishStrategy,Int64})
    precompile(Tuple{typeof(next_time),OnUpdateStrategy,Int64})
    precompile(Tuple{typeof(next_time),PeriodicStrategy,Int64})
    precompile(Tuple{typeof(next_time),ScheduledStrategy,Int64})
    precompile(Tuple{typeof(next_time),RateLimitedStrategy,Int64})

    # =============================================================================
    # Communication Functions - High Frequency
    # =============================================================================

    # Proxy construction
    precompile(Tuple{typeof(StatusProxy),Aeron.ExclusivePublication})
    precompile(Tuple{typeof(PropertyProxy),Vector{Aeron.ExclusivePublication}})

    # Status event publishing functions
    precompile(Tuple{typeof(publish_status_event),AgentType,Symbol,String,Int64})
    precompile(Tuple{typeof(publish_status_event),AgentType,Symbol,Symbol,Int64})
    precompile(Tuple{typeof(publish_status_event),AgentType,Symbol,String})
    precompile(Tuple{typeof(publish_status_event),AgentType,Symbol,Symbol})

    # StatusProxy publishing - scalar types
    precompile(Tuple{typeof(publish_status_event),StatusProxy,Symbol,String,String,Int64,Int64})
    precompile(Tuple{typeof(publish_status_event),StatusProxy,Symbol,Symbol,String,Int64,Int64})
    precompile(Tuple{typeof(publish_status_event),StatusProxy,Symbol,Int64,String,Int64,Int64})
    precompile(Tuple{typeof(publish_status_event),StatusProxy,Symbol,Float64,String,Int64,Int64})
    precompile(Tuple{typeof(publish_status_event),StatusProxy,Symbol,Bool,String,Int64,Int64})

    # StatusProxy publishing - array types
    precompile(Tuple{typeof(publish_status_event),StatusProxy,Symbol,Vector{Float32},String,Int64,Int64})
    precompile(Tuple{typeof(publish_status_event),StatusProxy,Symbol,Vector{Int64},String,Int64,Int64})
    precompile(Tuple{typeof(publish_status_event),StatusProxy,Symbol,Array{Float32,3},String,Int64,Int64})

    # PropertyProxy publishing - scalar types
    precompile(Tuple{typeof(publish_property),PropertyProxy,Int,Symbol,String,String,Int64,Int64})
    precompile(Tuple{typeof(publish_property),PropertyProxy,Int,Symbol,Symbol,String,Int64,Int64})
    precompile(Tuple{typeof(publish_property),PropertyProxy,Int,Symbol,Int64,String,Int64,Int64})
    precompile(Tuple{typeof(publish_property),PropertyProxy,Int,Symbol,Float64,String,Int64,Int64})
    precompile(Tuple{typeof(publish_property),PropertyProxy,Int,Symbol,Bool,String,Int64,Int64})

    # PropertyProxy publishing - array types
    precompile(Tuple{typeof(publish_property),PropertyProxy,Int,Symbol,Vector{Float32},String,Int64,Int64})
    precompile(Tuple{typeof(publish_property),PropertyProxy,Int,Symbol,Vector{Int64},String,Int64,Int64})
    precompile(Tuple{typeof(publish_property),PropertyProxy,Int,Symbol,Array{Float32,3},String,Int64,Int64})

    # High-level proxy functions
    precompile(Tuple{typeof(publish_state_change),StatusProxy,Symbol,String,Int64,Int64})
    precompile(Tuple{typeof(publish_event_response),StatusProxy,Symbol,String,String,Int64,Int64})
    precompile(Tuple{typeof(publish_event_response),StatusProxy,Symbol,Symbol,String,Int64,Int64})
    precompile(Tuple{typeof(publish_event_response),StatusProxy,Symbol,Int64,String,Int64,Int64})
    precompile(Tuple{typeof(publish_event_response),StatusProxy,Symbol,Float64,String,Int64,Int64})
    precompile(Tuple{typeof(publish_event_response),StatusProxy,Symbol,Bool,String,Int64,Int64})
    precompile(Tuple{typeof(publish_property_update),PropertyProxy,PublicationConfig,PropertiesType,String,Int64,Int64})

    # =============================================================================
    # Aeron Communication Primitives
    # =============================================================================

    # Critical Aeron functions
    precompile(Tuple{typeof(try_claim),Aeron.ExclusivePublication,Int,Int})
    precompile(Tuple{typeof(offer),Aeron.ExclusivePublication,Vector{UInt8},Int})
    precompile(Tuple{typeof(offer),Aeron.ExclusivePublication,Tuple{Vector{UInt8},Vector{UInt8}},Int})

    # =============================================================================
    # Property Management API
    # =============================================================================

    # Property registration and management
    precompile(Tuple{typeof(register!),AgentType,Symbol,Int,PublishStrategy})
    precompile(Tuple{typeof(unregister!),AgentType,Symbol,Int})
    precompile(Tuple{typeof(unregister!),AgentType,Symbol})
    precompile(Tuple{typeof(isregistered),AgentType,Symbol})
    precompile(Tuple{typeof(isregistered),AgentType,Symbol,Int})
    precompile(Tuple{typeof(empty!),AgentType})

    # =============================================================================
    # Property Value Handling - Performance Critical
    # =============================================================================

    # Decode property values from messages
    precompile(Tuple{typeof(decode_property_value),EventMessageDecoder,Type{String}})
    precompile(Tuple{typeof(decode_property_value),EventMessageDecoder,Type{Int64}})
    precompile(Tuple{typeof(decode_property_value),EventMessageDecoder,Type{Float64}})
    precompile(Tuple{typeof(decode_property_value),EventMessageDecoder,Type{Bool}})
    precompile(Tuple{typeof(decode_property_value),EventMessageDecoder,Type{Symbol}})
    precompile(Tuple{typeof(decode_property_value),EventMessageDecoder,Type{Vector{Float32}}})
    precompile(Tuple{typeof(decode_property_value),EventMessageDecoder,Type{Array{Float32,3}}})

    # Set property values
    precompile(Tuple{typeof(set_property_value!),PropertiesType,Symbol,String,Type{String}})
    precompile(Tuple{typeof(set_property_value!),PropertiesType,Symbol,Int64,Type{Int64}})
    precompile(Tuple{typeof(set_property_value!),PropertiesType,Symbol,Float64,Type{Float64}})
    precompile(Tuple{typeof(set_property_value!),PropertiesType,Symbol,Bool,Type{Bool}})
    precompile(Tuple{typeof(set_property_value!),PropertiesType,Symbol,Vector{Float32},Type{Vector{Float32}}})
    precompile(Tuple{typeof(set_property_value!),PropertiesType,Symbol,Array{Float32,3},Type{Array{Float32,3}}})

    # Property handlers
    precompile(Tuple{typeof(on_property_write),AgentType,Symbol,EventMessageDecoder})
    precompile(Tuple{typeof(on_property_read),AgentType,Symbol,EventMessageDecoder})

    # =============================================================================
    # Agent State Machine and Event Dispatch
    # =============================================================================

    # Core dispatch function
    precompile(Tuple{typeof(dispatch!),AgentType,Symbol,Nothing})
    precompile(Tuple{typeof(dispatch!),AgentType,Symbol,EventMessageDecoder})
    precompile(Tuple{typeof(dispatch!),AgentType,Symbol,TensorMessageDecoder})
    precompile(Tuple{typeof(dispatch!),AgentType,Symbol,Int64})
    precompile(Tuple{typeof(dispatch!),AgentType,Symbol,String})
    precompile(Tuple{typeof(dispatch!),AgentType,Symbol,Exception})

    # =============================================================================
    # Agent Framework Interface
    # =============================================================================

    # Agent interface methods
    precompile(Tuple{typeof(Agent.name),AgentType})
    precompile(Tuple{typeof(Agent.on_start),AgentType})
    precompile(Tuple{typeof(Agent.on_close),AgentType})
    precompile(Tuple{typeof(Agent.on_error),AgentType,Exception})
    precompile(Tuple{typeof(Agent.do_work),AgentType})

    # =============================================================================
    # Adapter Construction and Operations
    # =============================================================================

    # Adapter creation
    precompile(Tuple{typeof(ControlStreamAdapter),Aeron.Subscription,PropertiesType,AgentType})
    precompile(Tuple{typeof(InputStreamAdapter),Aeron.Subscription,AgentType})

    # Adapter polling operations
    precompile(Tuple{typeof(poll),ControlStreamAdapter,Int})
    precompile(Tuple{typeof(poll),InputStreamAdapter,Int})
    precompile(Tuple{typeof(poll),Vector{InputStreamAdapter},Int})

    # =============================================================================
    # Communication Setup/Teardown - Updated for new architecture
    # =============================================================================

    # CommunicationResources operations
    precompile(Tuple{typeof(CommunicationResources),Aeron.Client,PropertiesType})
    precompile(Tuple{typeof(Base.close),CommunicationResources})
    precompile(Tuple{typeof(Base.isopen),CommunicationResources})

    # =============================================================================
    # Message Handlers and Pollers
    # =============================================================================

    # Polling functions
    precompile(Tuple{typeof(input_poller),AgentType})
    precompile(Tuple{typeof(control_poller),AgentType})
    precompile(Tuple{typeof(timer_poller),AgentType})

    # =============================================================================
    # Timer System Hot Paths - Updated with new exports
    # =============================================================================

    # Timer operations - now exported for extension services
    precompile(Tuple{typeof(schedule!),TimerType,Int64,Symbol})
    precompile(Tuple{typeof(schedule_at!),TimerType,Int64,Symbol})
    precompile(Tuple{typeof(cancel!),TimerType,Int64})
    precompile(Tuple{typeof(cancel!),TimerType,Symbol})

    # Internal timer operations
    precompile(Tuple{typeof(Timers.poll),Function,TimerType,AgentType})
    precompile(Tuple{typeof(Timers.schedule!),TimerType,Int64,Symbol})
    precompile(Tuple{typeof(Timers.schedule_at!),TimerType,Int64,Symbol})
    precompile(Tuple{typeof(Timers.cancel!),TimerType,Int64})
    precompile(Tuple{typeof(Timers.cancel!),TimerType,Symbol})

    # =============================================================================
    # Exception Types for Error Handling
    # =============================================================================

    # Exception construction and handling
    precompile(Tuple{typeof(AgentStateError),Symbol,String})
    precompile(Tuple{typeof(AgentCommunicationError),String})
    precompile(Tuple{typeof(AgentConfigurationError),String})
    precompile(Tuple{typeof(PublicationError),String,Symbol})
    precompile(Tuple{typeof(PublicationFailureError),String,Int})
    precompile(Tuple{typeof(ClaimBufferError),String,Int,Int,Int})
    precompile(Tuple{typeof(PublicationBackPressureError),String,Int,Int})
    precompile(Tuple{typeof(StreamNotFoundError),String,Int})
    precompile(Tuple{typeof(CommunicationNotInitializedError),String})
    precompile(Tuple{typeof(PropertyStore.PropertyNotFoundError),Symbol})
    precompile(Tuple{typeof(PropertyStore.PropertyTypeError),Symbol,Type,Type})

    # Exception display
    precompile(Tuple{typeof(Base.showerror),IO,AgentStateError})
    precompile(Tuple{typeof(Base.showerror),IO,AgentCommunicationError})
    precompile(Tuple{typeof(Base.showerror),IO,ClaimBufferError})
    precompile(Tuple{typeof(Base.showerror),IO,PublicationBackPressureError})

    # =============================================================================
    # LightSumTypes Operations (Critical for Performance)
    # =============================================================================

    # PublishStrategy variant access
    precompile(Tuple{typeof(LightSumTypes.variant),PublishStrategy})

    # =============================================================================
    # Message Codec Operations
    # =============================================================================

    # Message encoding/decoding - frequently used in hot paths
    precompile(Tuple{typeof(SpidersMessageCodecs.EventMessageEncoder),Vector{UInt8}})
    precompile(Tuple{typeof(SpidersMessageCodecs.EventMessageDecoder),Vector{UInt8}})
    precompile(Tuple{typeof(SpidersMessageCodecs.EventMessageDecoder),UnsafeArrays.UnsafeArray{UInt8}})
    precompile(Tuple{typeof(SpidersMessageCodecs.TensorMessageEncoder),Vector{UInt8}})
    precompile(Tuple{typeof(SpidersMessageCodecs.TensorMessageDecoder),Vector{UInt8}})
    precompile(Tuple{typeof(SpidersMessageCodecs.TensorMessageDecoder),UnsafeArrays.UnsafeArray{UInt8}})

    # =============================================================================
    # Clock Operations (High Frequency)
    # =============================================================================

    # Clock operations used in every work iteration
    precompile(Tuple{typeof(Clocks.fetch!),ClockType})
    precompile(Tuple{typeof(Clocks.time_nanos),ClockType})
    precompile(Tuple{typeof(Clocks.time_micros),ClockType})

    # ID generation
    precompile(Tuple{typeof(SnowflakeId.next_id),IdGenType})
end

# Execute precompilation
_precompile_testservice()
