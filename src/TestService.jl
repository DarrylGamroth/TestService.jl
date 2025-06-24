module TestService

using Aeron
using Agent
using Clocks
using EnumX
using Hsm
using ManagedProperties
using SnowflakeId
using SpidersFragmentFilters
using SpidersMessageCodecs
using StaticArrays
using TimerWheels
using UnsafeArrays
using ValSplit
using AllocProfilerCheck

const DEFAULT_FRAGMENT_COUNT_LIMIT = 10

include("properties.jl")
include("agent.jl")
include("states.jl")

export main, @allocated_barrier

function (@main)(ARGS)
    # md = Aeron.MediaDriver.launch()
    # Initialize Aeron
    # Aeron.MediaDriver.launch() do
    Aeron.Context() do context
        Aeron.Client(context) do client
            # Initialize the agent
            agent = ControlStateMachine(client)

            # Start the agent
            runner = AgentRunner(BackoffIdleStrategy(), agent)
            Agent.start_on_thread(runner)

            try
                wait(runner)
            catch e
                if e isa InterruptException
                    @info "Shutting down..." 
                else
                    println("Error: ", e)
                    @error "Exception caught:" exception = (e, catch_backtrace())
                end
            finally
                close(runner)
            end
        end
    end
    # end

    return 0
end

end # module TestService
