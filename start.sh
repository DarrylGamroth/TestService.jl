#!/bin/bash

# Set the environment variables
export JULIA_NUM_THREADS="auto"
export JULIA_PROJECT=@.
export HEARTBEAT_PERIOD_NS=100000000000 # 100 seconds
export STATUS_URI="aeron:udp?endpoint=0.0.0.0:40123"
export STATUS_STREAM_ID=1
export CONTROL_URI="aeron-spy:aeron:udp?endpoint=0.0.0.0:40123"
export CONTROL_STREAM_ID=2
export CONTROL_STREAM_FILTER="TestService"
export PUB_DATA_URI_1="aeron:udp?endpoint=localhost:40123"
export PUB_DATA_STREAM_1=3
export BLOCK_NAME="TestService"
export BLOCK_ID=367

# Run the Julia script
julia -e "using TestService" "$@"
