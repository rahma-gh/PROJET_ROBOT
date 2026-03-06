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
# Start CoppeliaSim with your scene
# ======================================
echo "======================================"
echo " Starting CoppeliaSim with your scene"
echo "======================================"

# Use the scene file and enable ZMQ
COPPELIA_CMD="/opt/coppelia/coppeliaSim -s0 -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 -GzmqRemoteApi.rpcAddress=0.0.0.0 /app/pick_and_place.ttt"

echo "Command: xvfb-run -a $COPPELIA_CMD"
echo "Starting at: $(date)"

# Start with xvfb
xvfb-run -a --server-args="-screen 0 1024x768x24" \
    $COPPELIA_CMD > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

# Wait for process to initialize
echo "Waiting for CoppeliaSim to initialize..."
sleep 10

# Check if process is still running
if ! kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "❌ ERROR: CoppeliaSim process died!"
    echo "Last 50 lines of log:"
    tail -50 coppeliasim.log
    exit 1
fi
echo "✅ CoppeliaSim process is running"

# ======================================
# Wait for ZMQ ports
# ======================================
echo "======================================"
echo " Waiting for ZMQ ports"
echo "======================================"

TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if netstat -tln 2>/dev/null | grep -q ":23000"; then
        echo "✅ Port 23000 is listening after ${ELAPSED}s"
        break
    fi
    echo "  waiting for port 23000... ${ELAPSED}s/${TIMEOUT}s"
    sleep 2
    ELAPSED=$((ELAPSED+2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "❌ ERROR: Port 23000 never opened"
    tail -50 coppeliasim.log
    exit 1
fi

# Wait a bit more for the scene to fully load
echo "Waiting for scene to fully load..."
sleep 5

# ======================================
# Test ZMQ connection to the scene
# ======================================
echo "======================================"
echo " Testing ZMQ connection to your scene"
echo "======================================"

cat > test_scene.py << 'EOF'
import time
import sys
try:
    from coppeliasim_zmqremoteapi_client import RemoteAPIClient
    print("✅ Imported RemoteAPIClient")
    
    # Connect to simulator
    client = RemoteAPIClient()
    sim = client.require('sim')
    
    print("\n🔍 Getting scene objects:")
    
    # Get all objects in the scene (different API for ZMQ)
    # Method 1: Get objects by type
    objects = sim.getObjects(0)  # 0 = all object types
    print(f"Found {len(objects)} objects in scene")
    
    # List first 20 objects with their names
    for i, obj in enumerate(objects[:20]):
        name = sim.getObjectAlias(obj)
        print(f"  {i}: {name} (handle: {obj})")
    
    # Check for UR10 specifically using different possible names
    ur10_found = False
    possible_names = ['UR10', 'UR10_robot', 'UR10Robot', 'ur10', '/UR10']
    
    for name in possible_names:
        try:
            ur10_handle = sim.getObject(name)
            print(f"\n✅ Found UR10 with name '{name}' (handle: {ur10_handle})")
            ur10_found = True
            break
        except:
            continue
    
    if not ur10_found:
        print("\n❌ UR10 not found with any common names")
        print("Available objects in scene:")
        # Try to get all objects and print their full paths
        for obj in objects[:20]:
            try:
                path = sim.getObjectPath(obj)
                print(f"  Object path: {path}")
            except:
                pass
    
    # Try to get object by type (if UR10 is a specific type)
    print("\n🔍 Getting all robot objects:")
    robot_handles = sim.getObjects(2)  # 2 = sim.object_robot_type
    for robot in robot_handles:
        robot_name = sim.getObjectAlias(robot)
        print(f"  Found robot: {robot_name}")
    
    # Get simulation time to verify connection
    sim_time = sim.getSimulationTime()
    print(f"\n✅ Connection verified. Simulation time: {sim_time}")
    
    sys.exit(0 if ur10_found else 1)
        
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
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
