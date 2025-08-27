# PropertyStore-specific exceptions
# Provides domain-specific error types for property operations

"""
    PropertyError

Base type for all property-related errors.
"""
abstract type PropertyError <: Exception end

"""
    PropertyNotFoundError(property_name::Symbol)

Thrown when attempting to access a property that doesn't exist.
"""
struct PropertyNotFoundError <: PropertyError
    property_name::Symbol
end

function Base.showerror(io::IO, e::PropertyNotFoundError)
    print(io, "PropertyNotFoundError: Property ':$(e.property_name)' not found")
end

"""
    PropertyTypeError(property_name::Symbol, expected_type::Type, actual_type::Type)

Thrown when attempting to set a property with an incompatible type.
"""
struct PropertyTypeError <: PropertyError
    property_name::Symbol
    expected_type::Type
    actual_type::Type
end

function Base.showerror(io::IO, e::PropertyTypeError)
    print(io, "PropertyTypeError: Property ':$(e.property_name)' expects $(e.expected_type), got $(e.actual_type)")
end

"""
    PropertyAccessError(property_name::Symbol, access_mode::String)

Thrown when attempting to access a property in a way that violates its access mode.
"""
struct PropertyAccessError <: PropertyError
    property_name::Symbol
    access_mode::String
end

function Base.showerror(io::IO, e::PropertyAccessError)
    print(io, "PropertyAccessError: Property ':$(e.property_name)' is $(e.access_mode)")
end

"""
    PropertyValidationError(property_name::Symbol, message::String)

Thrown when property validation fails.
"""
struct PropertyValidationError <: PropertyError
    property_name::Symbol
    message::String
end

function Base.showerror(io::IO, e::PropertyValidationError)
    print(io, "PropertyValidationError: Property ':$(e.property_name)' validation failed: $(e.message)")
end

"""
    EnvironmentVariableError(variable_name::String)

Thrown when a required environment variable is missing or invalid.
"""
struct EnvironmentVariableError <: PropertyError
    variable_name::String
end

function Base.showerror(io::IO, e::EnvironmentVariableError)
    print(io, "EnvironmentVariableError: Required environment variable '$(e.variable_name)' not found or invalid")
end
