module TestService

using Aeron
using Agent
using Clocks
using EnumX
using Logging
using StaticKV
using SpidersMessageCodecs
using SpidersFragmentFilters

include("PropertyStore/PropertyStore.jl")
using .PropertyStore

include("rtcagent.jl")

export main

Base.exit_on_sigint(false)

function (@main)(ARGS)
    launch_driver = parse(Bool, get(ENV, "LAUNCH_MEDIA_DRIVER", "false"))
    
    if launch_driver
        @info "Launching Aeron MediaDriver"
        Aeron.MediaDriver.launch() do
            run_agent()
        end
    else
        @info "Running with external MediaDriver"
        run_agent()
    end

    return 0
end

function run_agent()
    Aeron.Context() do context
        Aeron.Client(context) do client
            clock = CachedEpochClock(EpochClock())
            properties = Properties(clock)
            
            # Create communication resources
            comms = CommunicationResources(client, properties)
            
            # Inject communication resources into the agent
            agent = RtcAgent(comms, properties, clock)

            # Start the agent
            runner = AgentRunner(BackoffIdleStrategy(), agent)
            Agent.start_on_thread(runner, 2)

            try
                wait(runner)
            catch e
                if e isa InterruptException
                    @info "Shutting down..."
                else
                    @error "Exception caught:" exception = (e, catch_backtrace())
                end
            finally
                close(runner)
            end
        end
    end
end

end # module TestService