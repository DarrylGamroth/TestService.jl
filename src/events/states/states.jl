# State machine implementation
# This file includes all state handler files in the correct order
# Each state file contains its own @statedef declaration and handlers

# Include all state handler files
include("root.jl")
include("top.jl")
include("ready.jl")
include("stopped.jl")
include("processing.jl")
include("playing.jl")
include("paused.jl")
include("error.jl")
include("exit.jl")
