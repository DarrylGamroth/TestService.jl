# Agent-level exceptions
# This file defines agent-specific exceptions including communication errors

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
    AgentStateError(current_state::Symbol, attempted_operation::String)

Thrown when attempting an operation that is invalid in the current agent state.
"""
struct AgentStateError <: AgentError
    current_state::Symbol
    attempted_operation::String
end

function Base.showerror(io::IO, e::AgentStateError)
    print(io, "AgentStateError: Cannot perform '$(e.attempted_operation)' in state :$(e.current_state)")
end

"""
    AgentCommunicationError(message::String)

Thrown when agent communication setup or operations fail.
"""
struct AgentCommunicationError <: AgentError
    message::String
end

function Base.showerror(io::IO, e::AgentCommunicationError)
    print(io, "AgentCommunicationError: $(e.message)")
end

"""
    AgentConfigurationError(message::String)

Thrown when agent configuration is invalid or incomplete.
"""
struct AgentConfigurationError <: AgentError
    message::String
end

function Base.showerror(io::IO, e::AgentConfigurationError)
    print(io, "AgentConfigurationError: $(e.message)")
end

"""
    PublicationError(message::String, field::Symbol)

Thrown when property publication fails.
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
    ClaimBufferError(publication::String, length::Int, max_attempts::Int)

Thrown when unable to claim a buffer from an Aeron publication after maximum retry attempts.
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
    PublicationBackPressureError(publication::String, max_attempts::Int)

Thrown when unable to offer a buffer to an Aeron publication due to persistent back pressure.
"""
struct PublicationBackPressureError <: CommunicationError
    publication::String
    max_attempts::Int
end

function Base.showerror(io::IO, e::PublicationBackPressureError)
    print(io, "PublicationBackPressureError: Failed to offer buffer to publication $(e.publication) after $(e.max_attempts) attempts due to back pressure")
end

"""
    StreamNotFoundError(stream_name::String, stream_index::Int)

Thrown when attempting to access a stream that doesn't exist.
"""
struct StreamNotFoundError <: CommunicationError
    stream_name::String
    stream_index::Int
end

function Base.showerror(io::IO, e::StreamNotFoundError)
    print(io, "StreamNotFoundError: Stream '$(e.stream_name)' with index $(e.stream_index) not found")
end

"""
    CommunicationNotInitializedError(operation::String)

Thrown when attempting communication operations before communications are initialized.
"""
struct CommunicationNotInitializedError <: CommunicationError
    operation::String
end

function Base.showerror(io::IO, e::CommunicationNotInitializedError)
    print(io, "CommunicationNotInitializedError: Cannot perform '$(e.operation)' - communications not initialized")
end

"""
    PublicationFailureError(publication::String, max_attempts::Int)

Thrown when unable to offer a buffer to an Aeron publication due to unexpected errors.
"""
struct PublicationFailureError <: CommunicationError
    publication::String
    max_attempts::Int
end

function Base.showerror(io::IO, e::PublicationFailureError)
    print(io, "PublicationFailureError: Failed to offer buffer to publication $(e.publication) after $(e.max_attempts) attempts due to unexpected errors")
end

"""
    ClaimBackPressureError(publication::String, length::Int, max_attempts::Int)

Thrown when unable to claim a buffer from an Aeron publication due to persistent back pressure.
"""
struct ClaimBackPressureError <: CommunicationError
    publication::String
    length::Int
    max_attempts::Int
end

function Base.showerror(io::IO, e::ClaimBackPressureError)
    print(io, "ClaimBackPressureError: Failed to claim buffer of length $(e.length) from publication $(e.publication) after $(e.max_attempts) attempts due to back pressure")
end
