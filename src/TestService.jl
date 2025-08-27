module TestService

using Revise
using Aeron
using Agent
using EnumX
using Logging

include("rtcagent.jl")

export main, RtcAgent, 
    PublishStrategy, OnUpdate, Periodic, Scheduled, RateLimited,
    OnUpdateStrategy, PeriodicStrategy, ScheduledStrategy, RateLimitedStrategy,
    should_publish, next_time, property_poller, timer_poller,
    register!, unregister!, isregistered, list, get_publication,
    # Communication and Property types
    CommunicationResources, Properties,
    # Timer functions  
    schedule!, schedule_at!, cancel!,
    # Exception types  
    AgentError, AgentStateError, AgentStartupError, ClaimBufferError,
    CommunicationError, CommunicationNotInitializedError, StreamNotFoundError,
    PublicationBackPressureError, SubscriptionError, MessageProcessingError

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
            # Initialize the agent
            agent = RtcAgent(client)

            # Start the agent
            runner = AgentRunner(BackoffIdleStrategy(), agent)
            Agent.start_on_thread(runner)

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