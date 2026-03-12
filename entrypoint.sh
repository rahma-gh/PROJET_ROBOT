#!/bin/bash
set -e

echo "=== DEBUG: Testing CoppeliaSim in container ==="
echo "System info:"
uname -a
cat /etc/os-release

echo "=== Testing Xvfb ==="
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' /opt/coppelia/coppeliaSim --version

echo "=== Testing CoppeliaSim without scene ==="
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
    /opt/coppelia/coppeliaSim -h -q -s0 &
COPPELIA_PID=$!

sleep 5

if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "✓ CoppeliaSim runs without scene"
    kill -TERM $COPPELIA_PID
    sleep 2
else
    echo "❌ CoppeliaSim crashed without scene"
    exit 1
fi

echo "=== Testing ZMQ server with minimal scene ==="

# Create a minimal scene script
cat > /tmp/minimal_scene.lua << 'EOF'
function sysCall_init()
    print("[MINIMAL] Scene initialized")
    sim.setSimulationTimestep(0.05)
end

function sysCall_actuation()
    -- Do nothing
end

function sysCall_sensing()
    -- Do nothing
end
EOF

# Create a minimal scene file (empty but with embedded script)
cat > /tmp/minimal.ttt << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<coppeliasim>
  <version>4.7.0</version>
  <sceneName>Minimal Test Scene</sceneName>
  <objects>
    <object>
      <handle>0</handle>
      <type>script</type>
      <script>
        <embedded>1</embedded>
        <code><![CDATA[
function sysCall_init()
    print("[SCENE] Minimal scene running")
    sim.setSimulationTimestep(0.05)
end

function sysCall_actuation() end
function sysCall_sensing() end
        ]]></code>
      </script>
    </object>
  </objects>
</coppeliasim>
EOF

echo "=== Starting CoppeliaSim with ZMQ ==="
xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
    /opt/coppelia/coppeliaSim \
    -h \
    -s99999999 \
    -q \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    -f /tmp/minimal.ttt \
    > /tmp/coppelia.log 2>&1 &
COPPELIA_PID=$!

echo "Waiting for ZMQ port..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if python3 -c "import socket; socket.create_connection(('localhost',23000),timeout=1)" 2>/dev/null; then
        echo "✓ Port 23000 open at ${ELAPSED}s"
        break
    fi
    
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ CoppeliaSim crashed"
        cat /tmp/coppelia.log
        exit 1
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED+2))
    echo "waiting... ${ELAPSED}s"
done

echo "=== Testing ZMQ connection ==="
python3 - << 'EOF'
import zmq
import time
import json

ctx = zmq.Context()
sock = ctx.socket(zmq.REQ)
sock.connect("tcp://localhost:23000")
sock.setsockopt(zmq.RCVTIMEO, 5000)
sock.setsockopt(zmq.SNDTIMEO, 5000)

print("Sending test request...")
sock.send_json({"func": "simGetSimulationTime", "args": []})

print("Waiting for response...")
response = sock.recv_json()
print(f"Response received: {response}")

if "result" in response:
    print("✓ ZMQ connection successful!")
else:
    print("❌ Unexpected response:", response)
EOF

ZMQ_TEST=$?

if [ $ZMQ_TEST -eq 0 ]; then
    echo "✓ All tests passed!"
    kill -TERM $COPPELIA_PID
    exit 0
else
    echo "❌ ZMQ test failed"
    echo "=== CoppeliaSim log ==="
    cat /tmp/coppelia.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi
