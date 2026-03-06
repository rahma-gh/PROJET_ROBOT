#!/bin/bash
set -e

echo "======================================"
echo " Initializing environment"
echo "======================================"

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

export PYTHONPATH=/app

echo "======================================"
echo " Starting CoppeliaSim (headless)"
echo "======================================"

xvfb-run -a /opt/coppelia/coppeliaSim \
    -h \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    -GzmqRemoteApi.rpcAddress=0.0.0.0 \
    /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

echo "======================================"
echo " Waiting for ZMQ Remote API server"
echo "======================================"

TIMEOUT=120
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do

    if grep -q "ZMQ remote API server" coppeliasim.log 2>/dev/null; then
        echo "ZMQ addon detected in log"
        break
    fi

    sleep 2
    ELAPSED=$((ELAPSED+2))
    echo "  waiting... ${ELAPSED}s / ${TIMEOUT}s"

done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: ZMQ addon never appeared in log"
    cat coppeliasim.log
    kill -9 $COPPELIA_PID || true
    exit 1
fi


echo "======================================"
echo " Waiting for RPC port 23000"
echo "======================================"

python3 << 'PY'
import socket, time, sys

deadline = time.time() + 90

while time.time() < deadline:
    try:
        s = socket.create_connection(("localhost",23000),2)
        s.close()
        print("ZMQ RPC port is OPEN")
        sys.exit(0)
    except Exception:
        time.sleep(1)

print("ERROR: rpc port 23000 never opened", file=sys.stderr)
sys.exit(1)
PY

if [ $? -ne 0 ]; then
    echo "======================================"
    echo " ZMQ connection failed"
    echo "======================================"
    cat coppeliasim.log
    kill -9 $COPPELIA_PID || true
    exit 1
fi


echo "======================================"
echo " Running pytest"
echo "======================================"

if [ -d "/app/tests" ]; then
    TEST_PATH="tests"
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


echo "======================================"
echo " Stopping CoppeliaSim"
echo "======================================"

kill -TERM $COPPELIA_PID 2>/dev/null || true
sleep 5

if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "Force killing CoppeliaSim"
    kill -9 $COPPELIA_PID || true
fi

echo "======================================"
echo " Tests finished (exit code $TEST_EXIT_CODE)"
echo "======================================"

echo "Last 20 lines of simulator log:"
tail -n 20 coppeliasim.log || true

exit $TEST_EXIT_CODE
