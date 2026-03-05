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

# Step 1: Wait for the port to open
until netstat -tuln 2>/dev/null | grep -q ":23000" || [ $ELAPSED -ge $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "  waiting for port... (${ELAPSED}s / ${TIMEOUT}s)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: CoppeliaSim ZMQ port 23000 did not open after ${TIMEOUT}s"
    tail -n 40 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "Port 23000 is open. Probing ZMQ API..."

# Step 2: Write the probe to a file so the process exits cleanly (no timeout kill)
# and always closes the ZMQ socket with linger=0 before exiting.
# A killed process (via `timeout 5s`) leaves the REQ socket half-open on the
# server side, which blocks the next RemoteAPIClient connection indefinitely.
cat > /tmp/zmq_probe.py << 'PYEOF'
import sys
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

c = None
rc = 1
try:
    c = RemoteAPIClient(host='localhost', port=23000)
    s = c.require('sim')
    state = s.getSimulationState()
    print(f"ZMQ API ready — simulation state: {state}")
    rc = 0
except Exception as e:
    print(f"Not ready: {type(e).__name__}: {e}", file=sys.stderr)
    rc = 1
finally:
    try:
        c.socket.close(linger=0)
        c.context.term()
    except Exception:
        pass
sys.exit(rc)
PYEOF

PROBE_TIMEOUT=120
PROBE_ELAPSED=0

until python3 /tmp/zmq_probe.py; do
    sleep $INTERVAL
    PROBE_ELAPSED=$((PROBE_ELAPSED + INTERVAL))
    echo "  ZMQ not ready yet... (${PROBE_ELAPSED}s / ${PROBE_TIMEOUT}s)"
    if [ $PROBE_ELAPSED -ge $PROBE_TIMEOUT ]; then
        echo "ERROR: ZMQ Remote API did not respond after ${PROBE_TIMEOUT}s"
        echo ""
        echo "Last 40 lines of coppeliasim.log:"
        tail -n 40 coppeliasim.log
        kill -TERM $COPPELIA_PID 2>/dev/null || true
        exit 1
    fi
done

echo "ZMQ Remote API is ready and responding."
sleep 2

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