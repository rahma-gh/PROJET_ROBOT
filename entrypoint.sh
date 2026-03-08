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

# Start CoppeliaSim with scene file properly loaded
# The -f flag is used to specify the scene file
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -h \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    -f /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ Remote API server to be ready ==="

TIMEOUT=120
ELAPSED=0
PORT_FOUND=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    if python3 -c "import socket; socket.create_connection(('localhost', 23000), timeout=1)" 2>/dev/null; then
        echo "✓ Port 23000 is accepting connections!"
        
        # Wait a bit for the server to fully initialize
        echo "  Waiting 5s for server to fully stabilize..."
        sleep 5
        
        # Check if process is still alive
        if ! kill -0 $COPPELIA_PID 2>/dev/null; then
            echo "❌ CoppeliaSim process died after port opened!"
            echo "=== CoppeliaSim Log ==="
            cat coppeliasim.log
            exit 1
        fi
        
        echo "  CoppeliaSim ZMQ server is ready"
        PORT_FOUND=1
        break
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo "  waiting for port... (${ELAPSED}s / ${TIMEOUT}s)"
    
    # Check if process is still alive
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "ERROR: CoppeliaSim process exited unexpectedly!"
        echo "=== CoppeliaSim Log ==="
        cat coppeliasim.log
        exit 1
    fi
done

if [ $PORT_FOUND -eq 0 ]; then
    echo "ERROR: Port 23000 never opened after ${TIMEOUT}s"
    echo "=== CoppeliaSim Log ==="
    cat coppeliasim.log
    exit 1
fi

echo "=== CoppeliaSim is ready, Tests can now run ==="

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
tail -n 20 coppeliasim.log

exit $TEST_EXIT_CODE
