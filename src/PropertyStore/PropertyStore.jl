module PropertyStore

# Disable precompilation for this module since it reads environment variables
# at macro expansion time, which would write values into precompiled code
__precompile__(false)

using Logging
using StaticKV

export Properties
export PropertyError, PropertyNotFoundError, PropertyTypeError, PropertyAccessError, PropertyValidationError, EnvironmentVariableError

include("exceptions.jl")
include("utilities.jl")
include("kvstore.jl")

end # module PropertyStore