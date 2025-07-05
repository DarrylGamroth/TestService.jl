# MessagingSystem Design Document

## Overview

The MessagingSystem module consolidates Aeron-based communication utilities from EventSystem and PropertiesSystem. This is a **practical, incremental approach** that starts by consolidating the most straightforward shared utilities.

## Phase 1 Approach: Consolidate Core Utilities

Rather than attempting a complex unified interface, we start by extracting the **generic, system-independent utilities** that both systems already use:

### What Phase 1 Consolidates
- **Message encoding functions**: `publish_value()` and `send_event_response()` 
- **Aeron retry logic**: `try_claim()` and `offer()` with consistent error handling
- **SBE message formatting**: Common patterns for EventMessage and TensorMessage encoding

### Key Insight
The `publish_value()` function from PropertiesSystem is **already generic** - it doesn't depend on PropertiesSystem types at all. It just takes basic parameters and handles SBE encoding + Aeron publication.

## MessagingSystem Module (Phase 1)

```julia
module MessagingSystem

export publish_value, try_claim, offer, send_event_response

# Generic publication utilities (from PropertiesSystem publish.jl)
function publish_value(field::Symbol, value, tag::AbstractString, correlation_id::Int64, 
                      timestamp_ns::Int64, publication, buffer::AbstractArray{UInt8}, 
                      position_ptr::Base.RefValue{Int64})
    # Handles both scalar values (EventMessage) and arrays (TensorMessage)
    # Already fully generic - no system dependencies
end

# Generic event response utilities (from EventSystem)  
function send_event_response(publication, buffer::Vector{UInt8}, position_ptr::Base.RefValue{Int64},
                           event::Symbol, value, timestamp_ns::Int64, correlation_id::Int64, agent_name::String)
    # Consolidated EventSystem send patterns
    # Multiple methods for different value types
end

# Generic Aeron utilities (from both systems)
function try_claim(publication, length, max_attempts=10)
    # Consolidated retry logic for buffer claiming
end

function offer(publication, buffer, max_attempts=10) 
    # Consolidated retry logic for publication
end

end # module MessagingSystem
```

## Integration Examples

### EventSystem Integration
```julia
# Import shared utilities
using ..MessagingSystem

# Replace existing send_event_response calls - now uses same parameter order as publish_value
function send_event_response(em::EventManager, event, value)
    if em.comms === nothing
        @warn "Cannot send event response: communication resources not initialized"
        return
    end

    # Use shared utility with consistent parameter ordering
    # Multiple dispatch will call the right method based on value type
    MessagingSystem.send_event_response(
        event,                    # field/event (same position as publish_value)
        value,                    # value (same position) - dispatch handles scalar vs array
        em.properties[:Name],     # tag/agent_name (same position) 
        em.correlation_id,        # correlation_id (same position)
        time_nanos(em.clock),     # timestamp_ns (same position)
        em.comms.status_stream,   # publication (same position)
        em.comms.buf,             # buffer (same position)
        em.position_ptr           # position_ptr (same position)
    )
end

# Replace existing offer/try_claim calls
function offer(p, buf, max_attempts=10)
    MessagingSystem.offer(p, buf, max_attempts)
end

function try_claim(p, length, max_attempts=10)
    MessagingSystem.try_claim(p, length, max_attempts)
end
```

### PropertiesSystem Integration
```julia
# Import shared utilities  
using ..MessagingSystem

# PropertiesSystem already uses the right pattern! No changes needed:
# publish_value(field, value, name, id, timestamp, stream, buffer, position_ptr)

# Just remove duplicated functions from publish.jl and import from MessagingSystem:
# - try_claim() -> use MessagingSystem.try_claim()
# - offer() -> use MessagingSystem.offer()
# - publish_value() -> use MessagingSystem.publish_value()
```

## Migration Strategy

### Phase 1: Extract Common Utilities (CURRENT)
- ✅ Created MessagingSystem module with `publish_value`, `send_event_response`, `try_claim`, `offer`
- ✅ All functions are generic and don't depend on specific system types
- Next: Update EventSystem and PropertiesSystem to import and use these utilities

### Phase 2: Migrate to Shared Utilities
- Update EventSystem to use `MessagingSystem.send_event_response()` instead of local versions
- Update EventSystem to use `MessagingSystem.try_claim()` and `MessagingSystem.offer()`
- Update PropertiesSystem to remove duplicated `try_claim()` and `offer()` from publish.jl
- PropertiesSystem already uses compatible `publish_value()` - just import from MessagingSystem

### Phase 3: Validate and Clean Up
- Run all tests to ensure no behavioral changes
- Remove duplicated code from both systems
- Update documentation

### Future Phases (Optional)
- Consider consolidating publication setup utilities if beneficial
- Add shared monitoring/diagnostics if needed

## Benefits of Phase 1 Approach

- **Low risk**: Only extracts already-generic utilities
- **High value**: Eliminates substantial code duplication immediately  
- **No system changes**: Both systems can adopt incrementally
- **Proven patterns**: Uses existing, working code patterns
- **Type stable**: All functions maintain their current type stability

## Success Metrics

- **No behavior changes**: All existing tests pass without modification
- **Code reduction**: Remove ~100+ lines of duplicated retry/encoding logic
- **Drop-in replacement**: `publish_value` works exactly as before
- **Maintained performance**: No regression in message throughput or allocations
