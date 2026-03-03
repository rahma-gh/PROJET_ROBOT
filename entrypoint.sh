#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR

echo "=== Starting CoppeliaSim ==="

xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
/opt/coppelia/coppeliaSim -h /app/pick_and_place.ttt &

COPPELIA_PID=$!

echo "CoppeliaSim PID: $COPPELIA_PID"

echo "=== Waiting for simulator to be ready ==="

# Wait until Remote API server opens port 23000 (ZMQ)
TIMEOUT=60
SECONDS_WAITED=0

while ! netstat -tuln | grep -q 23000; do
   sleep 2
   SECONDS_WAITED=$((SECONDS_WAITED+2))
   echo "Waiting... ${SECONDS_WAITED}s"
   if [ $SECONDS_WAITED -ge $TIMEOUT ]; then
       echo "ERROR: Simulator did not start in time"
       kill $COPPELIA_PID
       exit 1
   fi
done

echo "Simulator ready."

echo "=== Running Tests ==="

pytest tests/ --html=report.html --self-contained-html
TEST_EXIT_CODE=$?

echo "=== Stopping CoppeliaSim ==="

kill $COPPELIA_PID
wait $COPPELIA_PID 2>/dev/null || true

echo "=== Finished ==="

exit $TEST_EXIT_CODE
