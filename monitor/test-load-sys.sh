#!/bin/bash

# Number of CPU cores to stress (adjust as needed)
NUM_CORES=$(nproc)

echo "Starting CPU load on $NUM_CORES cores. Press Ctrl+C to stop."

# Start background infinite loops to load each CPU core
for i in $(seq 1 $NUM_CORES); do
  while :; do :; done &
done

# Wait forever (or until Ctrl+C)
wait
