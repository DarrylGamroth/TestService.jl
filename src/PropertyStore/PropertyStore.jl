module PropertyStore

using Logging
using StaticKV

export Properties
export PropertyError, PropertyNotFoundError, PropertyTypeError, PropertyAccessError, PropertyValidationError, EnvironmentVariableError

include("exceptions.jl")
include("utilities.jl")
include("kvstore.jl")

end # module PropertyStore