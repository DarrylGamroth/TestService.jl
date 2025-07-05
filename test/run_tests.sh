#!/bin/bash

# Test runner script for TestService.jl
# Run from the project root directory

echo "Running TestService.jl tests..."
echo "==============================="

# Change to project directory
cd "$(dirname "$0")/.."

# Run tests
julia --project=. -e "using Pkg; Pkg.test()"

echo "Tests completed."
