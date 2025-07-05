#!/bin/bash

# Simple test runner for TestService.jl
# Run from the project root directory

echo "Running TestService.jl tests..."
echo "==============================="

# Change to project directory
cd "$(dirname "$0")/.."

# Run tests directly
julia --project=. test/runtests.jl

echo "Tests completed."
