#!/bin/bash
set -e

echo "=== DEBUG: Testing CoppeliaSim with built-in scene ==="
echo "System info:"
uname -a
cat /etc/os-release

echo "=== Testing with built-in scene (mobility scene) ==="
# Use a built-in scene that definitely works
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
    /opt/coppelia/coppeliaSim \
    -h \
    -s1 \
    -q \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    /opt/coppelia/scenes/mobility/mobility.ttt \
    > /tmp/coppelia.log 2>&1 &
COPPELIA_PID=$!

echo "CoppeliaSim PID: $COPPELIA_PID"

echo "=== Waiting for ZMQ server ==="
TIMEOUT=30
ELAPSED=0
PORT_FOUND=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    if python3 -c "import socket; socket.create_connection(('localhost',23000),timeout=1)" 2>/dev/null; then
        echo "✓ Port 23000 open at ${ELAPSED}s"
        PORT_FOUND=1
        break
    fi
    
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ CoppeliaSim crashed"
        echo "=== CoppeliaSim log ==="
        cat /tmp/coppelia.log
        exit 1
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED+2))
    echo "waiting... ${ELAPSED}s"
done

if [ $PORT_FOUND -eq 0 ]; then
    echo "❌ Port 23000 never opened"
    echo "=== CoppeliaSim log ==="
    cat /tmp/coppelia.log
    exit 1
fi

echo "=== Testing ZMQ connection with built-in scene ==="
python3 - << 'EOF'
import zmq
import time
import sys
import json

print("Attempting ZMQ connection...")
ctx = zmq.Context()
sock = ctx.socket(zmq.REQ)
sock.connect("tcp://localhost:23000")
sock.setsockopt(zmq.RCVTIMEO, 5000)
sock.setsockopt(zmq.SNDTIMEO, 5000)

try:
    # Try to get object list
    sock.send_json({"func": "simGetObjectList", "args": [0, 0]})
    response = sock.recv_json()
    print(f"Response: {json.dumps(response, indent=2)}")
    
    if "result" in response:
        print(f"✓ Found {len(response['result'])} objects")
        sys.exit(0)
    else:
        print("❌ Unexpected response")
        sys.exit(1)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
EOF

ZMQ_TEST=$?

if [ $ZMQ_TEST -eq 0 ]; then
    echo "✓ Environment works with built-in scene!"
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 0
else
    echo "❌ Even built-in scene fails"
    echo "=== Full CoppeliaSim log ==="
    cat /tmp/coppelia.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi
