# Set the environment variables
$env:JULIA_NUM_THREADS = "auto"
$env:JULIA_PROJECT = "@."
$env:STATUS_URI = "aeron:udp?endpoint=0.0.0.0:40123"
$env:STATUS_STREAM_ID = 1
$env:CONTROL_URI = "aeron:udp?endpoint=0.0.0.0:40123"
$env:CONTROL_STREAM_ID = 2
$env:CONTROL_STREAM_FILTER = "TestService"
$env:PUB_DATA_URI_1="aeron:udp?endpoint=localhost:40123"
$env:PUB_DATA_STREAM_1 = 3
$env:BLOCK_NAME = "TestService"
$env:BLOCK_ID = 367

# Run the Julia script
& "julia" -e "using TestService" $args
