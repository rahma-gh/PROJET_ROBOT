#!/bin/bash
set -e

echo "======================================"
echo " Initializing environment - LEGACY API APPROACH"
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
# Start CoppeliaSim with legacy remote API
# ======================================
echo "======================================"
echo " Starting CoppeliaSim with legacy remote API"
echo "======================================"

# Use -H for true headless mode, enable legacy remote API on port 19997
COPPELIA_CMD="/opt/coppelia/coppeliaSim -H -gremotApiPort=19997 /app/pick_and_place.ttt"

echo "Command: xvfb-run -a $COPPELIA_CMD"
echo "Starting at: $(date)"

# Start with xvfb
xvfb-run -a --server-args="-screen 0 1024x768x24" \
    $COPPELIA_CMD > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

echo "======================================"
echo " Waiting for legacy remote API server"
echo "======================================"

TIMEOUT=120
ELAPSED=0
API_DETECTED=false

# Watch for the remote API server starting
while [ $ELAPSED -lt $TIMEOUT ]; do
    if grep -q "Remote API server" coppeliasim.log 2>/dev/null; then
        echo "✅ Remote API server detected in log after ${ELAPSED}s"
        API_DETECTED=true
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

if [ "$API_DETECTED" = false ]; then
    echo "❌ ERROR: Remote API server never appeared in log"
    cat coppeliasim.log
    exit 1
fi

echo "======================================"
echo " Waiting for port 19997"
echo "======================================"

# Wait for port to be open with retries
PORT_TIMEOUT=30
PORT_ELAPSED=0
PORT_READY=false

while [ $PORT_ELAPSED -lt $PORT_TIMEOUT ]; do
    if python3 -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('localhost', 19997)); s.close(); print('port open')" 2>/dev/null; then
        echo "✅ Legacy remote API port 19997 is OPEN after ${PORT_ELAPSED}s"
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
    echo "  waiting for port 19997... ${PORT_ELAPSED}s / ${PORT_TIMEOUT}s"
done

if [ "$PORT_READY" = false ]; then
    echo "❌ ERROR: port 19997 never opened"
    echo "--- Last 50 lines of log ---"
    tail -50 coppeliasim.log
    echo "---------------------------"
    kill -9 $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "======================================"
echo " Testing legacy API connection"
echo "======================================"

# Install the legacy remote API Python bindings
echo "Installing legacy remote API Python bindings..."
mkdir -p /tmp/legacy_api
cp -r /opt/coppelia/programming/remoteApiBindings/python/python /tmp/legacy_api/
export PYTHONPATH=/tmp/legacy_api:$PYTHONPATH

cat > test_legacy.py << 'EOF'
import time
import sys
import os

# Add the legacy API to path
sys.path.append('/opt/coppelia/programming/remoteApiBindings/python/python')

try:
    from coppeliasim_remoteapi.remoteApi import remoteApi
    print("✅ Legacy remote API imported")
    
    # Initialize
    sim = remoteApi()
    clientID = sim.simxStart('127.0.0.1', 19997, True, True, 5000, 5)
    
    if clientID != -1:
        print(f"✅ Connected to simulator with client ID: {clientID}")
        
        # Get object handles
        res, ur10_handle = sim.simxGetObjectHandle(clientID, 'UR10', sim.simx_opmode_blocking)
        if res == 0:
            print(f"✅ Found UR10 with handle: {ur10_handle}")
            
            # Get joint positions
            print("\n🔧 UR10 Joint positions:")
            joint_names = ['UR10_joint1', 'UR10_joint2', 'UR10_joint3', 'UR10_joint4', 'UR10_joint5', 'UR10_joint6']
            for joint_name in joint_names:
                res, joint_handle = sim.simxGetObjectHandle(clientID, f'UR10/{joint_name}', sim.simx_opmode_blocking)
                if res == 0:
                    res, position = sim.simxGetJointPosition(clientID, joint_handle, sim.simx_opmode_blocking)
                    if res == 0:
                        print(f"  {joint_name}: {position}")
                    else:
                        print(f"  {joint_name}: could not get position")
                else:
                    print(f"  {joint_name}: not found")
        else:
            print("❌ UR10 not found")
            # List all objects
            print("\n📋 Listing all objects:")
            res, objects = sim.simxGetObjects(clientID, sim.sim_handle_all, sim.simx_opmode_blocking)
            if res == 0:
                for obj in objects:
                    res, name = sim.simxGetObjectName(clientID, obj, sim.simx_opmode_blocking)
                    if res == 0:
                        print(f"  Handle {obj}: {name}")
        
        # Cleanup
        sim.simxFinish(clientID)
        sys.exit(0)
    else:
        print("❌ Failed to connect to simulator")
        sys.exit(1)
        
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

python3 test_legacy.py
TEST_RESULT=$?

if [ $TEST_RESULT -ne 0 ]; then
    echo "❌ Legacy API test failed"
    echo "--- Last 50 lines of log ---"
    tail -50 coppeliasim.log
    echo "---------------------------"
    kill -9 $COPPELIA_PID 2>/dev/null || true
    exit 1
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
