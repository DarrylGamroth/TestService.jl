module PropertiesSystem

using Aeron
using Clocks
using Logging
using ManagedProperties
using SnowflakeId
using SpidersMessageCodecs
using LightSumTypes

# Include sub-modules in dependency order
include("utilities.jl")
include("properties.jl")
include("strategies.jl")
include("publish.jl")

# Export public interface
export Properties, ManagedProperties, PropertiesManager,
    PublishStrategy, LightSumTypes,
    OnUpdate, Periodic, Scheduled, RateLimited,
    register!, unregister!, list, clear!, setup_communications!, teardown_communications!,
    properties, is_communications_active, pub_stream_count, publication_count,
    poller

# Constants
const DEFAULT_PUBLICATION_BUFFER_SIZE = 256

# Property publication configuration - mutable for updating timestamps
Base.@kwdef mutable struct PropertyConfig
    field::Symbol
    stream::Aeron.Publication
    strategy::PublishStrategy  # Now uses LightSumTypes strategy
    last_published_ns::Int64 = -1
    next_scheduled_ns::Int64 = -1
end

# Type-stable publication registry using LightSumTypes
@sumtype PropertyConfigType(PropertyConfig)

# Properties Manager - centralizes properties and their associated communication resources
"""
    PropertiesManager{P<:Properties,C<:AbstractClock,I<:SnowflakeIdGenerator}

A manager that encapsulates properties along with their associated communication resources
and publication management. Provides a unified interface for property system operations.
"""
mutable struct PropertiesManager{P<:Properties,C<:AbstractClock,I<:SnowflakeIdGenerator}
    client::Aeron.Client
    # Core components
    properties::P
    clock::C
    id_generator::I

    # Communication resources
    pub_data_streams::Vector{Aeron.Publication}

    # Publication management
    registry::Vector{PropertyConfigType}
    buffer::Vector{UInt8}
    position_ptr::Base.RefValue{Int64}

    # State tracking
    communications_active::Bool

    function PropertiesManager(client::Aeron.Client,
        properties::P,
        clock::C,
        id_generator::I) where {P<:Properties,C<:AbstractClock,I<:SnowflakeIdGenerator}
        new{P,C,I}(
            client,
            properties,
            clock,
            id_generator,
            Aeron.Publication[],
            PropertyConfigType[],
            Vector{UInt8}(undef, DEFAULT_PUBLICATION_BUFFER_SIZE),
            Ref{Int64}(0),
            false     # communications_active
        )
    end
end

# Communication lifecycle management
"""
    setup_communications!(pm::PropertiesManager)

Set up communication resources for the properties manager.
"""
function setup_communications!(pm::PropertiesManager)
    if pm.communications_active
        @warn "Communications already active for PropertiesManager"
        return false
    end

    pm.pub_data_streams = setup_publications!(pm.properties, pm.client)
    pm.communications_active = true

    @info "PropertiesManager communications setup complete" stream_count = length(pm.pub_data_streams)
    return true
end

"""
    teardown_communications!(pm::PropertiesManager)

Tear down communication resources for the properties manager.
"""
function teardown_communications!(pm::PropertiesManager)
    if !pm.communications_active
        @warn "Communications not active for PropertiesManager"
        return false
    end

    close_publications!(pm.pub_data_streams)
    pm.communications_active = false

    @info "PropertiesManager communications teardown complete"
    return true
end

# Convenience accessors
"""
    properties(pm::PropertiesManager)

Get the properties instance from the manager.
"""
properties(pm::PropertiesManager) = pm.properties

"""
    is_communications_active(pm::PropertiesManager)

Check if communications are currently active.
"""
is_communications_active(pm::PropertiesManager) = pm.communications_active

"""
    pub_stream_count(pm::PropertiesManager)

Get the number of active publication streams.
"""
pub_stream_count(pm::PropertiesManager) = length(pm.pub_data_streams)

"""
    publication_count(pm::PropertiesManager)

Get the number of registered property publications.
"""
publication_count(pm::PropertiesManager) = length(pm.registry)

# Publication registry management
"""
    register!(pm::PropertiesManager, field::Symbol, pub_data_index::Int, strategy::PublishStrategy)

Register a property for publication using a PubData stream by index.
The pub_data_index corresponds to the PubDataURI/StreamID pair (1-based).
A property can be registered multiple times with different streams and strategies.
"""
function register!(pm::PropertiesManager,
    field::Symbol,
    pub_data_index::Int,
    strategy::PublishStrategy)

    # Check if the index is valid
    if pub_data_index < 1 || pub_data_index > length(pm.pub_data_streams)
        throw(ArgumentError("Invalid PubData index $pub_data_index. Valid range: 1-$(length(pm.pub_data_streams))"))
    end

    publication = pm.pub_data_streams[pub_data_index]

    # Create and add the configuration to the registry
    config = PropertyConfig(
        field,
        publication,
        strategy,
        -1,        # Never published
        -1         # No scheduled time
    )
    # Wrap in PropertyConfigType sum type for type-stable storage
    push!(pm.registry, PropertyConfigType(config))
    @info "Registered property publication" field strategy pub_data_index
end

"""
    unregister!(pm::PropertiesManager, field::Symbol, pub_data_index::Int)

Remove a specific property-stream registration from the publication registry.
"""
function unregister!(pm::PropertiesManager, field::Symbol, pub_data_index::Int)
    if pub_data_index < 1 || pub_data_index > length(pm.pub_data_streams)
        return false
    end

    publication = pm.pub_data_streams[pub_data_index]

    # Find and remove matching registrations
    initial_length = length(pm.registry)
    filter!(config_wrapper -> begin
        config = variant(config_wrapper)
        !(config.field == field && config.stream === publication)
    end, pm.registry)
    removed_count = initial_length - length(pm.registry)

    if removed_count > 0
        @info "Unregistered property publication" field pub_data_index count = removed_count
        return true
    end
    return false
end

"""
    unregister!(pm::PropertiesManager, field::Symbol)

Remove all registrations for a property field from the publication registry.
"""
function unregister!(pm::PropertiesManager, field::Symbol)
    initial_length = length(pm.registry)
    filter!(config_wrapper -> begin
        config = variant(config_wrapper)
        config.field != field
    end, pm.registry)
    removed_count = initial_length - length(pm.registry)

    if removed_count > 0
        @info "Unregistered all property publications" field count = removed_count
        return true
    end
    return false
end

"""
    list(pm::PropertiesManager)

Return a list of all currently registered property publications as (field, pub_data_index, strategy) tuples.
"""
function list(pm::PropertiesManager)
    results = Tuple{Symbol,Int,PublishStrategy}[]

    for config_wrapper in pm.registry
        config = variant(config_wrapper)
        # Find the pub_data_index for this publication
        pub_data_index = 0
        for (index, publication) in enumerate(pm.pub_data_streams)
            if publication === config.stream
                pub_data_index = index
                break
            end
        end

        push!(results, (config.field, pub_data_index, config.strategy))
    end

    return results
end

"""
    clear!(pm::PropertiesManager)

Clear all registered publications. Useful for testing or reset scenarios.
"""
function clear!(pm::PropertiesManager)
    count = length(pm.registry)
    empty!(pm.registry)
    @info "Cleared all property publications" count
    return count
end

# Publication processing
"""
    process_publication!(pm::PropertiesManager, config_wrapper::PropertyConfigType)

Process a single property publication with type stability using LightSumTypes.
Returns 1 if processed (regardless of whether published), 0 if skipped.
"""
@inline function process_publication!(pm::PropertiesManager, config_wrapper::PropertyConfigType)
    # Extract the concrete PropertyConfig using variant() for type-stable dispatch
    config = variant(config_wrapper)
    
    # Get current time for this publication cycle
    now = time_nanos(pm.clock)

    # Early exit if strategy says not to publish based on timing
    property_timestamp_ns = last_update(pm.properties, config.field)
    if !should_publish(config.strategy,
        config.last_published_ns,
        config.next_scheduled_ns,
        property_timestamp_ns,
        now)
        return 0
    end

    # Publish the current property value
    publish_value(
        config.field,
        pm.properties[config.field],
        pm.properties[:Name],
        next_id(pm.id_generator),
        now,
        config.stream,
        pm.buffer,
        pm.position_ptr
    )
    config.last_published_ns = now
    config.next_scheduled_ns = next_time(config.strategy, now)

    return 1
end

"""
    poller(pm::PropertiesManager) -> Int

Poll for property publications that need to be sent.
Returns the number of publications processed.
"""
function poller(pm::PropertiesManager)
    # If communications are not active or no publications are registered, nothing to do
    if !pm.communications_active || isempty(pm.registry)
        return 0
    end

    published_count = 0

    # Process each registered publication
    for config_wrapper in pm.registry
        published_count += process_publication!(pm, config_wrapper)
    end

    return published_count
end

# Precompile statements for performance
function _precompile()
    # Properties construction
    precompile(Tuple{typeof(Properties),CachedEpochClock{EpochClock}})

    # PropertiesManager construction and management
    precompile(Tuple{typeof(PropertiesManager),Aeron.Client,Properties{CachedEpochClock{EpochClock}},CachedEpochClock{EpochClock},SnowflakeIdGenerator{CachedEpochClock{EpochClock}}})
    precompile(Tuple{typeof(setup_communications!),PropertiesManager})
    precompile(Tuple{typeof(teardown_communications!),PropertiesManager})

    # Publication functions - updated to use new LightSumTypes strategies
    precompile(Tuple{typeof(register!),PropertiesManager,Symbol,Int,PublishStrategy})
    precompile(Tuple{typeof(unregister!),PropertiesManager,Symbol,Int})
    precompile(Tuple{typeof(unregister!),PropertiesManager,Symbol})
    precompile(Tuple{typeof(list),PropertiesManager})
    precompile(Tuple{typeof(clear!),PropertiesManager})

    # Polling functions - with PropertyConfigType sum type
    precompile(Tuple{typeof(poller),PropertiesManager})
    precompile(Tuple{typeof(process_publication!),PropertiesManager,PropertyConfigType})
    
    # LightSumTypes variant function for type-stable dispatch
    precompile(Tuple{typeof(variant),PropertyConfigType})
    precompile(Tuple{typeof(variant),PublishStrategy})

    # Publication strategy evaluation functions with LightSumTypes
    precompile(Tuple{typeof(should_publish),PublishStrategy,Int64,Int64,Int64,Int64})
    precompile(Tuple{typeof(should_publish),OnUpdateStrategy,Int64,Int64,Int64,Int64})
    precompile(Tuple{typeof(should_publish),PeriodicStrategy,Int64,Int64,Int64,Int64})
    precompile(Tuple{typeof(should_publish),ScheduledStrategy,Int64,Int64,Int64,Int64})
    precompile(Tuple{typeof(should_publish),RateLimitedStrategy,Int64,Int64,Int64,Int64})

    # Time calculation functions with LightSumTypes
    precompile(Tuple{typeof(next_time),PublishStrategy,Int64})
    precompile(Tuple{typeof(next_time),OnUpdateStrategy,Int64})
    precompile(Tuple{typeof(next_time),PeriodicStrategy,Int64})
    precompile(Tuple{typeof(next_time),ScheduledStrategy,Int64})
    precompile(Tuple{typeof(next_time),RateLimitedStrategy,Int64})

    # Strategy constructor functions
    precompile(Tuple{typeof(OnUpdate)})
    precompile(Tuple{typeof(Periodic),Int64})
    precompile(Tuple{typeof(Scheduled),Int64})
    precompile(Tuple{typeof(RateLimited),Int64})

    # Communication setup functions
    precompile(Tuple{typeof(setup_publications!),Properties,Aeron.Client})
    precompile(Tuple{typeof(close_publications!),Vector{Aeron.Publication}})

    # Publish value function for common types
    precompile(Tuple{typeof(publish_value),Symbol,Any,String,UInt64,Int64,Aeron.Publication,Vector{UInt8},Base.RefValue{Int64}})
end

# Call precompile function
_precompile()

end # module PropertiesSystem

