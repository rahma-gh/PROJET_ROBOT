#!/bin/bash
set -e

echo "======================================"
echo " Initializing environment - FINAL FIX"
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
# Create a keep-alive script content
# ======================================
echo "======================================"
echo " Creating keep-alive script"
echo "======================================"

KEEP_ALIVE_SCRIPT=$(cat << 'EOF'
-- Keep-alive script for headless mode
function sysCall_init()
    print("[KEEP_ALIVE] Initialized - keeping simulation alive")
end

function sysCall_actuation()
    -- This empty function keeps the script running
    -- Do nothing, just prevent exit
end

function sysCall_sensing()
    -- Also keep alive
end

-- Don't exit
return 0
EOF
)

# Escape the script for command line
KEEP_ALIVE_ESCAPED=$(echo "$KEEP_ALIVE_SCRIPT" | sed 's/"/\\"/g' | tr '\n' ' ')

# ======================================
# Start CoppeliaSim with your scene
# ======================================
echo "======================================"
echo " Starting CoppeliaSim with your scene"
echo "======================================"

# Use -c to execute the keep-alive script
# The script will run in the sandbox and keep the simulation alive
COPPELIA_CMD="/opt/coppelia/coppeliaSim -H -c \"$KEEP_ALIVE_ESCAPED\" -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 /app/pick_and_place.ttt"

echo "Command: xvfb-run -a $COPPELIA_CMD"
echo "Starting at: $(date)"

# Start with xvfb
xvfb-run -a --server-args="-screen 0 1024x768x24" \
    /opt/coppelia/coppeliaSim -H -c "$KEEP_ALIVE_SCRIPT" -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

echo "======================================"
echo " Waiting for ZMQ Remote API server"
echo "======================================"

TIMEOUT=120
ELAPSED=0
ZMQ_DETECTED=false
KEEP_ALIVE_DETECTED=false

# Watch for the ZMQ addon loading
while [ $ELAPSED -lt $TIMEOUT ]; do
    if grep -q "ZMQ remote API server" coppeliasim.log 2>/dev/null; then
        if [ "$ZMQ_DETECTED" = false ]; then
            echo "✅ ZMQ addon detected in log after ${ELAPSED}s"
            ZMQ_DETECTED=true
        fi
    fi
    
    if grep -q "KEEP_ALIVE] Initialized" coppeliasim.log 2>/dev/null; then
        if [ "$KEEP_ALIVE_DETECTED" = false ]; then
            echo "✅ Keep-alive script initialized after ${ELAPSED}s"
            KEEP_ALIVE_DETECTED=true
        fi
    fi
    
    # Check if both conditions are met
    if [ "$ZMQ_DETECTED" = true ] && [ "$KEEP_ALIVE_DETECTED" = true ]; then
        echo "✅ CoppeliaSim fully initialized after ${ELAPSED}s"
        break
    fi
    
    # Check if process is still running
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ ERROR: CoppeliaSim process died!"
        echo "--- Last 50 lines of log ---"
        tail -50 coppeliasim.log
        echo "---------------------------"
        exit 1
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED+2))
    echo "  waiting... ${ELAPSED}s / ${TIMEOUT}s"
done

if [ "$ZMQ_DETECTED" = false ] || [ "$KEEP_ALIVE_DETECTED" = false ]; then
    echo "❌ ERROR: CoppeliaSim not fully initialized"
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
    if python3 -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('localhost', 23000)); s.close(); print('port open')" 2>/dev/null; then
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

# Wait a bit more for everything to settle
echo "Waiting for everything to settle..."
sleep 3

echo "======================================"
echo " Testing basic connectivity"
echo "======================================"

cat > test_basic.py << 'EOF'
import time
import sys
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

print("✅ Imported RemoteAPIClient")

try:
    # Connect to simulator
    client = RemoteAPIClient()
    sim = client.require('sim')
    
    print("✅ Connected to simulator")
    
    # Get simulation time (this works even without simulation running)
    sim_time = sim.getSimulationTime()
    print(f"✅ Simulation time: {sim_time}")
    
    print("\n✅ Basic connectivity test passed!")
    sys.exit(0)
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

python3 test_basic.py
BASIC_TEST=$?

if [ $BASIC_TEST -ne 0 ]; then
    echo "❌ Basic connectivity test failed"
    echo "--- Last 50 lines of log ---"
    tail -50 coppeliasim.log
    echo "---------------------------"
    kill -9 $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "======================================"
echo " Testing UR10 robot"
echo "======================================"

cat > test_ur10.py << 'EOF'
import time
import sys
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

print("✅ Imported RemoteAPIClient")

# Connect to simulator
client = RemoteAPIClient()
sim = client.require('sim')

print("\n🔍 Looking for UR10 robot...")

# Try to get UR10 directly
try:
    ur10_handle = sim.getObject('/UR10')
    print(f"✅ Found UR10 with handle: {ur10_handle}")
    
    # Now start simulation to test robot movement
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
    
    # Stop simulation
    sim.stopSimulation()
    print("\n✅ UR10 test passed!")
    sys.exit(0)
    
except Exception as e:
    print(f"❌ Could not find UR10: {e}")
    
    # List all objects to help debug
    print("\n📋 Listing all objects in scene:")
    try:
        # Try to get all objects
        for i in range(100):
            try:
                name = sim.getObjectAlias(i)
                if name and name != "":
                    print(f"  Handle {i}: {name}")
            except:
                pass
    except Exception as e2:
        print(f"Error listing objects: {e2}")
    
    sys.exit(1)
EOF

python3 test_ur10.py
TEST_RESULT=$?

if [ $TEST_RESULT -ne 0 ]; then
    echo "⚠️  UR10 test failed. Please check if your pick_and_place.ttt contains a UR10 robot."
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
