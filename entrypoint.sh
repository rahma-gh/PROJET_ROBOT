#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# Use a built-in CoppeliaSim scene that exists
BUILTIN_SCENE="/opt/coppelia/scenes/pickAndPlaceDemo.ttt"

# Verify built-in scene exists
if [ ! -f "$BUILTIN_SCENE" ]; then
    echo "ERROR: Built-in scene not found at $BUILTIN_SCENE"
    echo "Available scenes:"
    ls -la /opt/coppelia/scenes/
    exit 1
fi

FILE_SIZE=$(stat -c%s "$BUILTIN_SCENE" 2>/dev/null || echo "unknown")
echo "✓ Using built-in scene: pickAndPlaceDemo.ttt (size: $FILE_SIZE bytes)"

echo "=== Starting CoppeliaSim (headless mode) with built-in scene ==="

# Clear log
> coppeliasim.log

xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
/opt/coppelia/coppeliaSim \
    -h \
    -s99999999 \
    -q \
    -GzmqRemoteApi.rpcPort=23000 \
    -GzmqRemoteApi.cntPort=23001 \
    -f "$BUILTIN_SCENE" \
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
    
    # Try a simple function that should work in any scene
    s.send_json({"func":"simGetSimulationTime","args":[]})
    response = s.recv_json()
    print(f"Response: {response}")
    
    if "result" in response:
        sys.exit(0)
    else:
        print(f"Unexpected response: {response}")
        sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF
        then
            echo "✓ ZMQ API READY with built-in scene"
            ZMQ_READY=1
            break
        fi
    fi

    sleep 2
    ELAPSED=$((ELAPSED+2))
    echo "waiting... ${ELAPSED}s"

    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ CoppeliaSim crashed"
        echo "=== Full CoppeliaSim log ==="
        cat coppeliasim.log
        exit 1
    fi
done

if [ $PORT_FOUND -eq 0 ] || [ $ZMQ_READY -eq 0 ]; then
    echo "ERROR: ZMQ server not ready"
    echo "=== Full CoppeliaSim log ==="
    cat coppeliasim.log
    exit 1
fi

echo "=== Simulator ready with built-in scene ==="

echo "Last simulator log lines:"
tail -15 coppeliasim.log

# Create a simple test script to verify the pick and place scene
cat > /tmp/test_pickandplace.py << 'EOF'
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

print("Testing connection to pickAndPlaceDemo scene...")
client = RemoteAPIClient()
sim = client.require('sim')

# Start simulation
print("Starting simulation...")
sim.startSimulation()
time.sleep(3)

# List objects in the scene
print("Objects in pick and place scene:")
objects = sim.getObjects(-1, 0)
object_names = []
for i, obj in enumerate(objects[:20]):  # First 20 objects
    name = sim.getObjectAlias(obj, 1)
    object_names.append(name)
    print(f"  {i+1}. {name} (handle: {obj})")

# Look for specific objects that might be in a pick and place scene
robot_found = False
for name in object_names:
    if "UR" in name or "robot" in name.lower() or "arm" in name.lower():
        print(f"✓ Found robot-related object: {name}")
        robot_found = True

if robot_found:
    print("✓ Scene contains robot objects")
else:
    print("⚠️ No robot objects found in first 20 objects")

print(f"\nTotal objects in scene: {len(objects)}")

if len(objects) > 10:
    print("✓ Scene loaded successfully with multiple objects")
else:
    print("⚠️ Scene might be empty or not loaded properly")

sim.stopSimulation()
print("Test completed")
EOF

echo "=== Testing built-in pick and place scene ==="
python3 /tmp/test_pickandplace.py
TEST_EXIT_CODE=$?

echo "=== Stopping simulator ==="
kill -TERM $COPPELIA_PID 2>/dev/null || true
sleep 5

if kill -0 $COPPELIA_PID 2>/dev/null; then
    kill -KILL $COPPELIA_PID
fi

echo "=== Full CoppeliaSim log ==="
cat coppeliasim.log

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "✓ SUCCESS: Built-in pick and place scene works in your environment!"
    echo "This means your Docker environment is good, but your custom scene (pick_and_place.ttt) has issues."
else
    echo "❌ FAILED: Even built-in pick and place scene crashes in your environment"
    echo "This means there's an issue with your Docker environment setup."
fi

exit $TEST_EXIT_CODE
