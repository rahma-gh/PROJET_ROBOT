#!/bin/bash
set -e

echo "======================================"
echo " Initializing environment - FINAL VERSION"
echo "======================================"
echo "Current directory: $(pwd)"
echo "User: $(whoami)"
echo "Date: $(date)"

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

export PYTHONPATH=/app
export DISPLAY=:99

# ======================================
# Clear old logs
# ======================================
rm -f coppeliasim.log

# ======================================
# Check if the scene file exists
# ======================================
echo "======================================"
echo " Checking scene file"
echo "======================================"
if [ ! -f "/app/pick_and_place.ttt" ]; then
    echo "❌ ERROR: Scene file /app/pick_and_place.ttt not found!"
    ls -la /app/
    exit 1
fi
echo "✅ Scene file found: /app/pick_and_place.ttt"
ls -la /app/pick_and_place.ttt

# ======================================
# Create a simple keep-alive script
# ======================================
echo "======================================"
echo " Creating keep-alive script"
echo "======================================"

cat > /tmp/keep_alive.lua << 'EOF'
-- Simple script to keep CoppeliaSim alive in headless mode
function sysCall_init()
    print("[KEEP_ALIVE] Starting keep-alive script")
    -- Don't start simulation automatically, just keep the process alive
end

function sysCall_actuation()
    -- This empty function keeps the script running
    -- and prevents CoppeliaSim from exiting
end

function sysCall_sensing()
    -- Also keep alive
end
EOF

# ======================================
# Start CoppeliaSim with your scene and keep-alive script
# ======================================
echo "======================================"
echo " Starting CoppeliaSim with your scene"
echo "======================================"

# Use -s to keep simulation running for a very long time (10^6 seconds ~ 11.5 days)
COPPELIA_CMD="/opt/coppelia/coppeliaSim -h -s1000000 -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 /app/pick_and_place.ttt"

echo "Command: xvfb-run -a $COPPELIA_CMD"
echo "Starting at: $(date)"

# Start with xvfb
xvfb-run -a --server-args="-screen 0 1024x768x24" \
    $COPPELIA_CMD > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

echo "======================================"
echo " Waiting for ZMQ Remote API server"
echo "======================================"

TIMEOUT=120
ELAPSED=0
ZMQ_DETECTED=false

# Watch for the ZMQ addon loading
while [ $ELAPSED -lt $TIMEOUT ]; do
    if grep -q "ZMQ remote API server" coppeliasim.log 2>/dev/null; then
        echo "✅ ZMQ addon detected in log after ${ELAPSED}s"
        ZMQ_DETECTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED+2))
    echo "  waiting for ZMQ addon... ${ELAPSED}s / ${TIMEOUT}s"
    
    # Check if process is still running
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ ERROR: CoppeliaSim process died!"
        echo "--- Last 50 lines of log ---"
        tail -50 coppeliasim.log
        echo "---------------------------"
        exit 1
    fi
done

if [ "$ZMQ_DETECTED" = false ]; then
    echo "❌ ERROR: ZMQ addon never appeared in log"
    cat coppeliasim.log
    exit 1
fi

echo "======================================"
echo " Waiting for RPC port 23000"
echo "======================================"

# Wait for port to be open with retries
PORT_TIMEOUT=30
PORT_ELAPSED=0
PORT_READY=false

while [ $PORT_ELAPSED -lt $PORT_TIMEOUT ]; do
    if python3 -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('localhost', 23000)); s.close()" 2>/dev/null; then
        echo "✅ ZMQ RPC port 23000 is OPEN after ${PORT_ELAPSED}s"
        PORT_READY=true
        break
    fi
    
    # Check if process died
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ ERROR: CoppeliaSim process died while waiting for port!"
        echo "--- Last 50 lines of log ---"
        tail -50 coppeliasim.log
        echo "---------------------------"
        exit 1
    fi
    
    sleep 2
    PORT_ELAPSED=$((PORT_ELAPSED+2))
    echo "  waiting for port 23000... ${PORT_ELAPSED}s / ${PORT_TIMEOUT}s"
done

if [ "$PORT_READY" = false ]; then
    echo "❌ ERROR: rpc port 23000 never opened"
    echo "--- Last 50 lines of log ---"
    tail -50 coppeliasim.log
    echo "---------------------------"
    kill -9 $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

# Wait a bit more for the scene to fully load
echo "Waiting for scene to fully load..."
sleep 5

echo "======================================"
echo " Testing scene objects"
echo "======================================"

cat > test_scene.py << 'EOF'
import time
import sys
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

print("✅ Imported RemoteAPIClient")

# Connect to simulator
client = RemoteAPIClient()
sim = client.require('sim')

print("\n🔍 Looking for UR10 robot...")

# Try to get UR10 directly (like in your main.py)
try:
    ur10_handle = sim.getObject('/UR10')
    print(f"✅ Found UR10 with handle: {ur10_handle}")
    
    # Now start simulation (this is what your main.py does)
    print("\n▶️ Starting simulation...")
    sim.startSimulation()
    time.sleep(2)
    
    # Get joint positions
    print("\n🔧 UR10 Joint positions:")
    joint_names = [
        'UR10_joint1', 'UR10_joint2', 'UR10_joint3', 
        'UR10_joint4', 'UR10_joint5', 'UR10_joint6'
    ]
    
    for joint_name in joint_names:
        try:
            joint_handle = sim.getObject(f'/UR10/{joint_name}')
            joint_pos = sim.getJointPosition(joint_handle)
            print(f"  {joint_name}: {joint_pos}")
        except Exception as e:
            print(f"  {joint_name}: not found - {e}")
    
    # Check conveyor sensor
    try:
        sensor = sim.getObject('/ConveyorSensor')
        print(f"\n✅ Found ConveyorSensor: {sensor}")
    except:
        print("\n⚠️ ConveyorSensor not found")
    
    # Stop simulation
    sim.stopSimulation()
    print("\n✅ Scene test passed!")
    sys.exit(0)
    
except Exception as e:
    print(f"❌ Could not find UR10: {e}")
    
    # List all objects to help debug
    print("\n📋 Listing all objects in scene:")
    try:
        # Get all objects
        for i in range(100):
            try:
                name = sim.getObjectAlias(i)
                if name and name != "":
                    obj_type = sim.getObjectType(i)
                    print(f"  Handle {i}: {name} (type: {obj_type})")
            except:
                pass
    except Exception as e2:
        print(f"Error listing objects: {e2}")
    
    sys.exit(1)
EOF

python3 test_scene.py
TEST_RESULT=$?

if [ $TEST_RESULT -ne 0 ]; then
    echo "⚠️  Scene test failed. Please check if your pick_and_place.ttt contains a UR10 robot."
    echo "Continuing with tests anyway..."
fi

# ======================================
# Run pytest
# ======================================
echo "======================================"
echo " Running pytest"
echo "======================================"

if [ -d "/app/tests" ]; then
    TEST_PATH="tests"
else
    TEST_PATH="."
fi

# Run tests
pytest $TEST_PATH \
    --html=report.html \
    --self-contained-html \
    --timeout=180 \
    --timeout-method=thread \
    -vv

TEST_EXIT_CODE=$?

# ======================================
# Generate a summary
# ======================================
echo "======================================"
echo " Test Summary"
echo "======================================"
echo "Exit code: $TEST_EXIT_CODE"
echo ""
echo "Last 20 lines of simulator log:"
echo "--------------------------------"
tail -20 coppeliasim.log
echo "--------------------------------"

# ======================================
# Cleanup
# ======================================
echo "======================================"
echo " Stopping CoppeliaSim"
echo "======================================"

kill -TERM $COPPELIA_PID 2>/dev/null || true
sleep 5
kill -9 $COPPELIA_PID 2>/dev/null || true

echo "✅ Done"

exit $TEST_EXIT_CODE
