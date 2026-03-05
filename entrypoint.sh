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

echo "Port 23000 is open. Probing ZMQ API and starting simulation..."

# Step 2: Probe AND start the simulation so CoppeliaSim is already running
# when pytest creates its own client. When stopped (state=0), CoppeliaSim
# can queue or drop subsequent ZMQ requests depending on the version.
cat > /tmp/zmq_probe.py << 'PYEOF'
import sys, time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

c = None
rc = 1
try:
    c = RemoteAPIClient(host='localhost', port=23000)
    s = c.require('sim')
    state = s.getSimulationState()
    print(f"Connected — simulation state: {state}")

    # Start the simulation here so it is already RUNNING when pytest connects.
    # The sim fixture will call startSimulation() again which is harmless
    # (it is a no-op if already running).
    if state == 0:
        print("Starting simulation from entrypoint probe...")
        s.startSimulation()
        time.sleep(2.0)
        state = s.getSimulationState()
        print(f"Simulation state after start: {state}")

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
        tail -n 40 coppeliasim.log
        kill -TERM $COPPELIA_PID 2>/dev/null || true
        exit 1
    fi
done

echo "ZMQ Remote API is ready and simulation is running."
sleep 1

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