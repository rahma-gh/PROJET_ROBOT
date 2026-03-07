#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

echo "=== Starting CoppeliaSim (headless mode) ==="

# Start CoppeliaSim with ZMQ ports configured
# Use -c flag to execute Lua command that starts the simulation
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -H \
    -c "sim.startSimulation()" \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ Remote API server to be ready ==="

TIMEOUT=120
ELAPSED=0

# Use the same connection test as pytest does (actually try to connect)
while [ $ELAPSED -lt $TIMEOUT ]; do
    if python3 -c "import socket; socket.create_connection(('localhost', 23000), timeout=1)" 2>/dev/null; then
        echo "✓ Port 23000 is accepting connections!"
        break
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo "  waiting for connection... (${ELAPSED}s / ${TIMEOUT}s)"
    
    # Check if process is still alive
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "ERROR: CoppeliaSim process exited unexpectedly!"
        echo "=== CoppeliaSim Log ==="
        cat coppeliasim.log
        exit 1
    fi
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: Port 23000 never opened after ${TIMEOUT}s"
    echo "=== CoppeliaSim Log (last 50 lines) ==="
    tail -n 50 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

sleep 2

echo "=== Running pytest ==="

export PYTHONPATH=/app

# Ensure output directory exists
mkdir -p /app/output

if [ -d "/app/tests" ]; then
    TEST_PATH="tests/"
else
    TEST_PATH="."
fi

pytest $TEST_PATH \
    --html=/app/output/report.html \
    --self-contained-html \
    --timeout=180 \
    --timeout-method=thread \
    -vv

TEST_EXIT_CODE=$?

echo "=== Stopping CoppeliaSim ==="

kill -TERM $COPPELIA_PID 2>/dev/null || true
timeout 8s wait $COPPELIA_PID 2>/dev/null || true

if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "CoppeliaSim still alive → force kill"
    kill -KILL $COPPELIA_PID 2>/dev/null || true
fi

echo "=== Test finished with exit code $TEST_EXIT_CODE ==="
echo "Last 20 lines of coppeliasim.log:"
tail -n 20 coppeliasim.log

exit $TEST_EXIT_CODE
