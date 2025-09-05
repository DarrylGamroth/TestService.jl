"""
    AgentError

Base type for all agent-level errors.
"""
abstract type AgentError <: Exception end

"""
    CommunicationError

Base type for all communication-related errors.
"""
abstract type CommunicationError <: AgentError end

"""
    AgentStateError

Thrown when attempting an operation invalid in the current agent state.

Contains the current state and the operation that was attempted for debugging.
"""
struct AgentStateError <: AgentError
    current_state::Symbol
    attempted_operation::String
end

function Base.showerror(io::IO, e::AgentStateError)
    print(io, "AgentStateError: Cannot perform '$(e.attempted_operation)' in state :$(e.current_state)")
end

"""
    AgentCommunicationError

Thrown when agent communication setup or operations fail.
"""
struct AgentCommunicationError <: AgentError
    message::String
end

function Base.showerror(io::IO, e::AgentCommunicationError)
    print(io, "AgentCommunicationError: $(e.message)")
end

"""
    AgentConfigurationError

Thrown when agent configuration is invalid or incomplete.
"""
struct AgentConfigurationError <: AgentError
    message::String
end

function Base.showerror(io::IO, e::AgentConfigurationError)
    print(io, "AgentConfigurationError: $(e.message)")
end

"""
    PublicationError

Thrown when property publication fails.

Contains the error message and the field that failed to publish.
"""
struct PublicationError <: AgentError
    message::String
    field::Symbol
end

function Base.showerror(io::IO, e::PublicationError)
    print(io, "PublicationError: Failed to publish property ':$(e.field)' - $(e.message)")
end

# Communication-specific exceptions

"""
    ClaimBufferError

Thrown when unable to claim a buffer from an Aeron publication.

Contains publication details, requested buffer length, and retry attempts
for debugging back pressure or resource contention issues.
"""
struct ClaimBufferError <: CommunicationError
    publication::String
    length::Int
    max_attempts::Int
end

function Base.showerror(io::IO, e::ClaimBufferError)
    print(io, "ClaimBufferError: Failed to claim buffer of length $(e.length) from publication $(e.publication) after $(e.max_attempts) attempts")
end

"""
    PublicationBackPressureError

Thrown when unable to offer a buffer due to persistent back pressure.

Indicates the Aeron publication is experiencing sustained high load.
"""
struct PublicationBackPressureError <: CommunicationError
    publication::String
    max_attempts::Int
end

function Base.showerror(io::IO, e::PublicationBackPressureError)
    print(io, "PublicationBackPressureError: Failed to offer buffer to publication $(e.publication) after $(e.max_attempts) attempts due to back pressure")
end

"""
    StreamNotFoundError

Thrown when attempting to access a stream that doesn't exist.

Contains the stream name and index for debugging configuration issues.
"""
struct StreamNotFoundError <: CommunicationError
    stream_name::String
    stream_index::Int
end

function Base.showerror(io::IO, e::StreamNotFoundError)
    print(io, "StreamNotFoundError: Stream '$(e.stream_name)' with index $(e.stream_index) not found")
end

"""
    CommunicationNotInitializedError

Thrown when attempting communication operations before initialization.
"""
struct CommunicationNotInitializedError <: CommunicationError
    operation::String
end

function Base.showerror(io::IO, e::CommunicationNotInitializedError)
    print(io, "CommunicationNotInitializedError: Cannot perform '$(e.operation)' - communications not initialized")
end

"""
    PublicationFailureError

Thrown when unable to offer a buffer due to unexpected errors.

Indicates an unexpected failure in the Aeron publication system.
"""
struct PublicationFailureError <: CommunicationError
    publication::String
    max_attempts::Int
end

function Base.showerror(io::IO, e::PublicationFailureError)
    print(io, "PublicationFailureError: Failed to offer buffer to publication $(e.publication) after $(e.max_attempts) attempts due to unexpected errors")
end

"""
    ClaimBackPressureError

Thrown when unable to claim a buffer due to persistent back pressure.

Similar to `ClaimBufferError` but specifically indicates back pressure conditions.
"""
struct ClaimBackPressureError <: CommunicationError
    publication::String
    length::Int
    max_attempts::Int
end

function Base.showerror(io::IO, e::ClaimBackPressureError)
    print(io, "ClaimBackPressureError: Failed to claim buffer of length $(e.length) from publication $(e.publication) after $(e.max_attempts) attempts due to back pressure")
end
