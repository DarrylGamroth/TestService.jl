# Mock Aeron module for testing
# This module provides mock implementations of Aeron types and functions
# to avoid dependencies on the real Aeron library during testing

module Aeron
export Context, Client, Publication, Subscription, FragmentHandler, FragmentAssembler, BufferClaim
export add_publication, add_subscription, poll, try_claim, offer, is_connected
export FragmentHandler, FragmentAssembler
export PUBLICATION_NOT_CONNECTED, PUBLICATION_BACK_PRESSURED, PUBLICATION_ADMIN_ACTION, PUBLICATION_CLOSED, PUBLICATION_MAX_POSITION_EXCEEDED, PUBLICATION_ERROR

# Aeron result constants
const PUBLICATION_NOT_CONNECTED = -1
const PUBLICATION_BACK_PRESSURED = -2
const PUBLICATION_ADMIN_ACTION = -3
const PUBLICATION_CLOSED = -4
const PUBLICATION_MAX_POSITION_EXCEEDED = -5
const PUBLICATION_ERROR = -6

struct Context
end

function Context(f::Function)
    c = Context()
    try
        f(c)
    finally
        close(c)
    end
end

Base.close(::Context) = nothing

# Mock Aeron types
struct Client
    context::Context
end

function Client(f::Function, context)
    c = Client(context)
    try
        f(c)
    finally
        close(c)
    end
end

function Client(f::Function)
    Context() do context
        c = Client(context)
        try
            f(c)
        finally
            close(c)
        end
    end
end

Base.close(::Client) = nothing

const aeron_publication_t = Cvoid
struct Publication
    publication::Ptr{aeron_publication_t}
    client::Client
    is_owned::Bool

    function Publication(publication::Ptr{aeron_publication_t}, client::Client, is_owned::Bool=false)
        return new(publication, client, is_owned)
    end
end

const aeron_subscription_t = Cvoid
struct Subscription
    subscription::Ptr{aeron_subscription_t}
    client::Client
    is_owned::Bool

    function Subscription(subscription::Ptr{aeron_subscription_t}, client::Client, is_owned::Bool=false)
        return new(subscription, client, is_owned)
    end
end

struct FragmentHandler
    handler::Function
    context::Any
end

struct FragmentAssembler
    handler::FragmentHandler
end

# Mock BufferClaim - simplified version
struct BufferClaim
    data::Vector{UInt8}
    offset::Int
    length::Int

    BufferClaim(length::Int) = new(Vector{UInt8}(undef, length), 0, length)
end

# Mock Aeron functions
add_publication(c::Client, uri::AbstractString, stream_id) = Publication(Ptr{aeron_publication_t}(), c, true)
add_subscription(c::Client, uri::AbstractString, stream_id) = Subscription(Ptr{aeron_subscription_t}(), c, true)

function poll(subscription::Subscription, handler::FragmentAssembler, limit::Int)
    return 0  # No fragments to process in tests
end

is_connected(pub::Publication) = true

function try_claim(pub::Publication, length::Int)
    # Return a mock claim and positive result (successful claim)
    return (BufferClaim(length), length)
end

function offer(pub::Publication, buffer::Vector{UInt8})
    return length(buffer)  # Return the length to simulate successful offer
end

function offer(pub::Publication, buffer)
    return 100  # Return positive value to simulate successful offer
end

# For cleanup
Base.close(::Publication) = nothing
Base.close(::Subscription) = nothing

# Buffer operations for BufferClaim
function Base.unsafe_wrap(::Type{Array{UInt8,1}}, claim::BufferClaim, length::Int)
    return view(claim.data, 1:min(length, claim.length))
end

# Commit operation (no-op for mock)
function commit(claim::BufferClaim)
    return nothing
end

# Abort operation (no-op for mock)
function abort(claim::BufferClaim)
    return nothing
end
end
