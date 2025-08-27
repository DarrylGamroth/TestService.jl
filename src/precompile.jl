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
    
    # RtcAgent construction
    precompile(Tuple{typeof(RtcAgent),Aeron.Client,PropertiesType,ClockType})
    precompile(Tuple{typeof(RtcAgent),Aeron.Client,PropertiesType})
    
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
    precompile(Tuple{typeof(PublicationConfig),Symbol,Aeron.Publication,Int,PublishStrategy,Int64,Int64})
    precompile(Tuple{typeof(OnUpdate)})
    precompile(Tuple{typeof(Periodic),Int64})
    precompile(Tuple{typeof(Scheduled),Int64})
    precompile(Tuple{typeof(RateLimited),Int64})

    # =============================================================================
    # Hot Path Functions - Property Publishing
    # =============================================================================
    
    # Property publication - critical hot path
    precompile(Tuple{typeof(publish_property!),AgentType,PublicationConfig})
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
    
    # Message publishing functions
    precompile(Tuple{typeof(publish_value),Symbol,String,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_value),Symbol,Int64,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_value),Symbol,Float64,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_value),Symbol,Bool,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_value),Symbol,Symbol,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    
    # Array publishing (tensor messages)
    precompile(Tuple{typeof(publish_value),Symbol,Vector{Float32},String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_value),Symbol,Array{Float32,3},String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_value),Symbol,Vector{Int64},String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    
    # Event publishing variants
    precompile(Tuple{typeof(publish_event),Symbol,String,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_event),Symbol,Int64,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_event),Symbol,Symbol,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_event),Symbol,Bool,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
    precompile(Tuple{typeof(publish_event),Symbol,Float64,String,Int64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})

    # Utility functions for event responses
    precompile(Tuple{typeof(send_event_response),AgentType,Symbol,String})
    precompile(Tuple{typeof(send_event_response),AgentType,Symbol,Int64})
    precompile(Tuple{typeof(send_event_response),AgentType,Symbol,Float64})
    precompile(Tuple{typeof(send_event_response),AgentType,Symbol,Bool})
    precompile(Tuple{typeof(send_event_response),AgentType,Symbol,Symbol})

    # =============================================================================
    # Aeron Communication Primitives
    # =============================================================================
    
    # Critical Aeron functions
    precompile(Tuple{typeof(try_claim),Aeron.Publication,Int,Int})
    precompile(Tuple{typeof(offer),Aeron.Publication,Vector{UInt8},Int})
    precompile(Tuple{typeof(offer),Aeron.Publication,Tuple{Vector{UInt8},Vector{UInt8}},Int})

    # =============================================================================
    # Property Management API
    # =============================================================================
    
    # Property registration and management
    precompile(Tuple{typeof(register!),AgentType,Symbol,Int,PublishStrategy})
    precompile(Tuple{typeof(unregister!),AgentType,Symbol,Int})
    precompile(Tuple{typeof(unregister!),AgentType,Symbol})
    precompile(Tuple{typeof(isregistered),AgentType,Symbol})
    precompile(Tuple{typeof(isregistered),AgentType,Symbol,Int})
    precompile(Tuple{typeof(list),AgentType})
    precompile(Tuple{typeof(empty!),AgentType})
    precompile(Tuple{typeof(get_publication),AgentType,Int})

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
    precompile(Tuple{typeof(handle_property_write),AgentType,PropertiesType,Symbol,EventMessageDecoder})
    precompile(Tuple{typeof(handle_property_read),AgentType,PropertiesType,Symbol,EventMessageDecoder})

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
    # Communication Setup/Teardown
    # =============================================================================
    
    # Communication lifecycle
    precompile(Tuple{typeof(Base.open),AgentType})
    precompile(Tuple{typeof(Base.close),AgentType})
    precompile(Tuple{typeof(Base.isopen),AgentType})
    precompile(Tuple{typeof(CommunicationResources),Aeron.Client,PropertiesType,AgentType})

    # =============================================================================
    # Message Handlers and Pollers
    # =============================================================================
    
    # Fragment handlers
    precompile(Tuple{typeof(control_handler),AgentType,Vector{UInt8},Nothing})
    precompile(Tuple{typeof(data_handler),AgentType,Vector{UInt8},Nothing})
    
    # Polling functions
    precompile(Tuple{typeof(input_poller),AgentType})
    precompile(Tuple{typeof(control_poller),AgentType})
    precompile(Tuple{typeof(timer_poller),AgentType})

    # =============================================================================
    # Timer System Hot Paths
    # =============================================================================
    
    # Timer operations
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
    precompile(Tuple{typeof(SpidersMessageCodecs.TensorMessageEncoder),Vector{UInt8}})
    precompile(Tuple{typeof(SpidersMessageCodecs.TensorMessageDecoder),Vector{UInt8}})

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
