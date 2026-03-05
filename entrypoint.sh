#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

echo "=== Starting CoppeliaSim (headless mode) ==="

xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -h \
    -q \
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

# Wait for the ZMQ server log message — no Python probe needed.
# Opening a RemoteAPIClient connection and then closing it corrupts the
# REQ/REP state on the server side for the next caller.
# Instead we watch the CoppeliaSim log for the line it prints when the
# ZMQ remote API server is fully initialised and ready to accept clients.
until grep -q "ZeroMQ remote API server" coppeliasim.log 2>/dev/null \
   || grep -q "zmqRemoteApi" coppeliasim.log 2>/dev/null \
   || grep -q "Remote API" coppeliasim.log 2>/dev/null \
   || [ $ELAPSED -ge $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "  waiting for ZMQ ready log line... (${ELAPSED}s / ${TIMEOUT}s)"
    # Show last log line for visibility
    tail -n 1 coppeliasim.log 2>/dev/null || true
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: CoppeliaSim ZMQ server did not signal readiness after ${TIMEOUT}s"
    tail -n 40 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "CoppeliaSim ZMQ server is ready (detected in log)."

# Extra wait for scene objects to be fully loaded
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