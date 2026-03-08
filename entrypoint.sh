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

# Try to detect if file is valid (should start with CoppeliaSim markers)
if command -v file &> /dev/null; then
    echo "✓ File format detected: $(file -b /app/pick_and_place.ttt)"
else
    echo "✓ File found (file utility not available for format check)"
fi

# Check CoppeliaSim version and plugins
echo "=== CoppeliaSim Diagnostics ==="
echo "Version: $(/opt/coppelia/coppeliaSim --version 2>&1 || echo 'Version info not available')"
echo "Available plugins:"
ls -la /opt/coppelia/ | grep -E "plugin|remote" || echo "No plugins found"

# Check for ZMQ plugin specifically
if [ -f "/opt/coppelia/libsimExtZMQRemoteApi.so" ]; then
    echo "✓ ZMQ Remote API plugin found"
else
    echo "⚠️  ZMQ Remote API plugin not found - checking elsewhere"
    find /opt/coppelia -name "*ZMQ*" -o -name "*zmq*" 2>/dev/null | head -10 || echo "No ZMQ files found"
fi

echo "=== Starting CoppeliaSim (headless mode) with full logging ==="

# Clear old log
> coppeliasim.log

# Start CoppeliaSim with verbose output and capture logs
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -h \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    -Gverbose=1 \
    /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

# Monitor process in background
(
    sleep 10
    if kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "✓ Process still alive after 10s initial check"
    else
        echo "❌ Process died within first 10 seconds!"
        echo "=== Exit code: $(wait $COPPELIA_PID 2>/dev/null; echo $?)"
        echo "=== Full log content ==="
        cat coppeliasim.log
        exit 1
    fi
) &

echo "=== Waiting for ZMQ Remote API server to be ready ==="

TIMEOUT=120
ELAPSED=0
PORT_FOUND=0

# Use the same connection test as pytest does (actually try to connect)
while [ $ELAPSED -lt $TIMEOUT ]; do
    if python3 -c "import socket; socket.create_connection(('localhost', 23000), timeout=1)" 2>/dev/null; then
        echo "✓ Port 23000 is accepting connections!"
        
        # Additional check: try ZMQ handshake
        echo "  Testing ZMQ API handshake..."
        if python3 -c "
import zmq
import json
context = zmq.Context()
socket = context.socket(zmq.REQ)
socket.connect('tcp://localhost:23000')
# Try to get version info
socket.send_json({'func': 'simGetStringParam', 'args': [0]})  # sim_stringparam_application_version
if socket.poll(3000):
    response = socket.recv_json()
    print(f'    ✓ ZMQ API responding: {response}')
    exit(0)
else:
    print('    ❌ ZMQ API not responding')
    exit(1)
" 2>&1; then
            echo "  ✓ ZMQ API fully operational!"
        else
            echo "  ⚠️  Port open but ZMQ API not responding - server may be stuck"
        fi
        
        echo "  Waiting 15s for server to fully stabilize..."
        sleep 15
        
        # Check if process is still alive after waiting
        if ! kill -0 $COPPELIA_PID 2>/dev/null; then
            echo "❌ CoppeliaSim process died during stabilization period!"
            echo "=== Exit code: $(wait $COPPELIA_PID 2>/dev/null; echo $?)"
            echo "=== Last 50 lines of log ==="
            tail -50 coppeliasim.log
            echo "=== Full log ==="
            cat coppeliasim.log
            exit 1
        fi
        
        echo "  CoppeliaSim ZMQ server should now be fully ready for all tests"
        PORT_FOUND=1
        break
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo "  waiting for port... (${ELAPSED}s / ${TIMEOUT}s)"
    
    # Check if process is still alive
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "ERROR: CoppeliaSim process exited unexpectedly!"
        echo "=== Exit code: $(wait $COPPELIA_PID 2>/dev/null; echo $?)"
        echo "=== CoppeliaSim Log (full) ==="
        cat coppeliasim.log
        exit 1
    fi
done

if [ $PORT_FOUND -eq 0 ]; then
    echo "ERROR: Port 23000 never opened after ${TIMEOUT}s"
    echo "=== CoppeliaSim Log (full) ==="
    cat coppeliasim.log
    echo ""
    echo "=== Checking if process is still running ==="
    ps aux | grep coppeliaSim | grep -v grep || echo "CoppeliaSim process not found - it crashed!"
    kill -TERM $COPPELIA_PID 2>/dev/null || true
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
echo "=== Last 20 lines of coppeliasim.log ==="
tail -n 20 coppeliasim.log
echo "=== First 20 lines of coppeliasim.log ==="
head -n 20 coppeliasim.log

exit $TEST_EXIT_CODE
