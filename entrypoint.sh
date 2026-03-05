#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

echo "=== Starting CoppeliaSim (headless mode) ==="

# Note: no -q flag — it causes CoppeliaSim to exit immediately after loading
# the scene without waiting for the simulation to run.
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -h \
    -G zmqRemoteApi.rpcPort=23000 \
    -G zmqRemoteApi.cntPort=23001 \
    /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ Remote API server to be ready ==="

TIMEOUT=120
INTERVAL=2
ELAPSED=0

# Watch for the exact log line CoppeliaSim prints when the ZMQ addon is loaded
until grep -q "ZMQ remote API server" coppeliasim.log 2>/dev/null \
   || [ $ELAPSED -ge $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "  waiting... (${ELAPSED}s / ${TIMEOUT}s)"
    tail -n 1 coppeliasim.log 2>/dev/null || true
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: ZMQ remote API server did not appear in log after ${TIMEOUT}s"
    tail -n 40 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "CoppeliaSim ZMQ server addon loaded. Waiting for scene to settle..."
sleep 3

echo "=== Running pytest ==="

export PYTHONPATH=/app

if [ -d "/app/tests" ]; then
    TEST_PATH="tests/"
else
    TEST_PATH="."
fi

pytest $TEST_PATH \
    --html=report.html \
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