#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# Verify scene file exists and is readable
if [ ! -f "/app/pick_and_place.ttt" ]; then
    echo "ERROR: Scene file /app/pick_and_place.ttt not found!"
    echo "Files in /app:"
    ls -lah /app/ | grep -E "\.ttt|\.lua"
    exit 1
fi

# Check file integrity
FILE_SIZE=$(stat -c%s /app/pick_and_place.ttt 2>/dev/null || echo "unknown")
echo "✓ Scene file found: /app/pick_and_place.ttt (size: $FILE_SIZE bytes)"

echo "=== Starting CoppeliaSim (headless mode) ==="

# Clear old log
> coppeliasim.log

# Start CoppeliaSim with scene file and proper initialization
# First load the scene, then start the ZMQ server, then keep alive
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -h \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    -f /app/pick_and_place.ttt \
    -c "simZMQRemoteApi.start(23000); while true do sim.wait(1) end" > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ Remote API server to be ready ==="

TIMEOUT=120
ELAPSED=0
PORT_FOUND=0
ZMQ_READY=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    if python3 -c "import socket; socket.create_connection(('localhost', 23000), timeout=1)" 2>/dev/null; then
        echo "✓ Port 23000 is accepting connections at ${ELAPSED}s!"
        
        # Wait a bit for the server to fully initialize
        echo "  Waiting 5s for server to fully stabilize..."
        sleep 5
        
        # Check if process is still alive
        if ! kill -0 $COPPELIA_PID 2>/dev/null; then
            echo "❌ CoppeliaSim process died after port opened!"
            echo "=== Full CoppeliaSim Log ==="
            cat coppeliasim.log
            exit 1
        fi
        
        # Verify ZMQ is actually responding with a proper handshake
        echo "  Testing ZMQ API handshake..."
        if python3 -c "
import zmq
import json
import sys
import time

try:
    context = zmq.Context()
    socket = context.socket(zmq.REQ)
    socket.connect('tcp://localhost:23000')
    socket.setsockopt(zmq.RCVTIMEO, 5000)
    socket.setsockopt(zmq.SNDTIMEO, 5000)
    
    # Try to get version info
    socket.send_json({'func': 'simGetStringParam', 'args': [0]})  # sim_stringparam_application_version
    response = socket.recv_json()
    print(f'    ✓ ZMQ API responding: {response}')
    sys.exit(0)
except zmq.ZMQError as e:
    print(f'    ❌ ZMQ error: {e}')
    sys.exit(1)
except Exception as e:
    print(f'    ❌ Error: {e}')
    sys.exit(1)
" 2>&1; then
            echo "  ✓ ZMQ API fully operational!"
            ZMQ_READY=1
            break
        else
            echo "  ⚠️  ZMQ API test failed - server may not be fully ready"
            echo "  Checking log for scene loading errors..."
            tail -20 coppeliasim.log | grep -E "error|warning|load|scene" || true
        fi
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo "  waiting for port... (${ELAPSED}s / ${TIMEOUT}s)"
    
    # Check if process is still alive
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "ERROR: CoppeliaSim process exited unexpectedly at ${ELAPSED}s!"
        echo "=== Exit code: $(wait $COPPELIA_PID 2>/dev/null; echo $?)"
        echo "=== Full CoppeliaSim Log ==="
        cat coppeliasim.log
        exit 1
    fi
done

if [ $PORT_FOUND -eq 0 ] && [ $ZMQ_READY -eq 0 ]; then
    echo "ERROR: Port 23000 never opened or ZMQ never responded after ${TIMEOUT}s"
    echo "=== Full CoppeliaSim Log ==="
    cat coppeliasim.log
    echo ""
    echo "=== Checking if process is still running ==="
    ps aux | grep coppeliaSim | grep -v grep || echo "CoppeliaSim process not found - it crashed!"
    exit 1
fi

echo "=== CoppeliaSim is ready, Tests can now run ==="
echo "=== Current log status (looking for scene loading) ==="
if [ -f coppeliasim.log ]; then
    echo "=== Lines containing 'scene' or 'load' ==="
    grep -i "scene\|load" coppeliasim.log | tail -20 || echo "No scene loading messages found"
    echo "=== Last 15 lines of log ==="
    tail -15 coppeliasim.log
else
    echo "Log file not found"
fi

echo "=== Running pytest ==="

export PYTHONPATH=/app
export PYTHONUNBUFFERED=1

# Ensure output directory exists
mkdir -p /app/output

# Determine test path
if [ -d "/app/tests" ]; then
    TEST_PATH="tests/"
else
    TEST_PATH="."
fi

# Run pytest with verbose output and shorter timeout for faster feedback
pytest $TEST_PATH \
    --html=/app/output/report.html \
    --self-contained-html \
    --timeout=180 \
    --timeout-method=thread \
    -vv \
    --maxfail=1

TEST_EXIT_CODE=$?

echo "=== Stopping CoppeliaSim ==="

# Graceful shutdown
kill -TERM $COPPELIA_PID 2>/dev/null || true
timeout 8s wait $COPPELIA_PID 2>/dev/null || true

# Force kill if still alive
if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "CoppeliaSim still alive → force kill"
    kill -KILL $COPPELIA_PID 2>/dev/null || true
fi

echo "=== Test finished with exit code $TEST_EXIT_CODE ==="

# Always show the full log at the end for debugging
echo "=== Complete CoppeliaSim Log ==="
if [ -f coppeliasim.log ]; then
    cat coppeliasim.log
else
    echo "Log file not found"
fi

exit $TEST_EXIT_CODE
