#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# Verify scene file exists
if [ ! -f "/app/pick_and_place.ttt" ]; then
    echo "ERROR: Scene file /app/pick_and_place.ttt not found!"
    echo "Files in /app:"
    ls -lah /app/ | grep -E "\.ttt|\.lua"
    exit 1
fi

FILE_SIZE=$(stat -c%s /app/pick_and_place.ttt 2>/dev/null || echo "unknown")
echo "✓ Scene file found (size: $FILE_SIZE bytes)"

echo "=== Starting CoppeliaSim (headless mode) ==="

# Clear log
> coppeliasim.log

# Start simulator
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
/opt/coppelia/coppeliaSim \
    -h \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    /app/pick_and_place.ttt \
    > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim launched (PID: $COPPELIA_PID)"

echo "=== Waiting for ZMQ Remote API server ==="

TIMEOUT=120
ELAPSED=0
PORT_FOUND=0
ZMQ_READY=0

while [ $ELAPSED -lt $TIMEOUT ]; do

    if python3 -c "import socket; socket.create_connection(('localhost',23000),timeout=1)" 2>/dev/null; then
        PORT_FOUND=1
        echo "✓ Port 23000 open at ${ELAPSED}s"

        sleep 5

        if ! kill -0 $COPPELIA_PID 2>/dev/null; then
            echo "❌ CoppeliaSim process died!"
            cat coppeliasim.log
            exit 1
        fi

        echo "Testing ZMQ handshake..."

        if python3 - <<EOF
import zmq,sys
try:
    ctx=zmq.Context()
    s=ctx.socket(zmq.REQ)
    s.connect("tcp://localhost:23000")
    s.setsockopt(zmq.RCVTIMEO,5000)
    s.setsockopt(zmq.SNDTIMEO,5000)
    s.send_json({"func":"simGetSimulationTime","args":[]})
    s.recv_json()
    sys.exit(0)
except Exception as e:
    print(e)
    sys.exit(1)
EOF
        then
            echo "✓ ZMQ API READY"
            ZMQ_READY=1
            break
        fi
    fi

    sleep 2
    ELAPSED=$((ELAPSED+2))
    echo "waiting... ${ELAPSED}s"

    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ CoppeliaSim crashed"
        cat coppeliasim.log
        exit 1
    fi
done

if [ $PORT_FOUND -eq 0 ] || [ $ZMQ_READY -eq 0 ]; then
    echo "ERROR: ZMQ server not ready"
    cat coppeliasim.log
    exit 1
fi

echo "=== Simulator ready ==="

echo "Last simulator log lines:"
tail -15 coppeliasim.log

echo "=== Running pytest ==="

export PYTHONPATH=/app
export PYTHONUNBUFFERED=1

mkdir -p /app/output

if [ -d "/app/tests" ]; then
    TEST_PATH="tests/"
else
    TEST_PATH="."
fi

pytest $TEST_PATH \
    --html=/app/output/report.html \
    --self-contained-html \
    -vv \
    --maxfail=1

TEST_EXIT_CODE=$?

echo "=== Stopping simulator ==="

kill -TERM $COPPELIA_PID 2>/dev/null || true
sleep 5

if kill -0 $COPPELIA_PID 2>/dev/null; then
    kill -KILL $COPPELIA_PID
fi

echo "=== Tests finished with code $TEST_EXIT_CODE ==="

echo "=== Full CoppeliaSim log ==="
cat coppeliasim.log

exit $TEST_EXIT_CODE
