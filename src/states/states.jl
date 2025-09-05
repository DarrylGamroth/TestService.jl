"""
State machine implementation for RtcAgent hierarchical state management.

Includes all state handler files in dependency order. Each state file contains
its own state definitions and event handlers for the agent lifecycle.
"""

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
