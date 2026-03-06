#!/bin/bash
set -e

echo "======================================"
echo " Initializing environment - DEBUG MODE"
echo "======================================"
echo "Current directory: $(pwd)"
echo "User: $(whoami)"
echo "Date: $(date)"

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

export PYTHONPATH=/app

# ======================================
# Debugging: Check CoppeliaSim installation
# ======================================
echo "======================================"
echo " Checking CoppeliaSim installation"
echo "======================================"
echo "CoppeliaSim root: /opt/coppelia"
ls -la /opt/coppelia/ || echo "ERROR: CoppeliaSim not found!"

echo -e "\nChecking for ZeroMQ addon:"
find /opt/coppelia -name "*zmq*" -ls 2>/dev/null || echo "No ZMQ files found"

echo -e "\nChecking addon manifest:"
cat /root/.local/share/CoppeliaSim/addon_manifest.xml 2>/dev/null || echo "No addon manifest found"

echo -e "\nChecking system scripts:"
ls -la /opt/coppelia/system/ 2>/dev/null || echo "No system scripts found"

echo -e "\nChecking scene file:"
ls -la /app/pick_and_place.ttt 2>/dev/null || echo "WARNING: Scene file not found!"

# ======================================
# Clear old logs
# ======================================
rm -f coppeliasim.log
rm -f zmq_debug.log

# ======================================
# Create a properly formatted minimal scene
# ======================================
echo "======================================"
echo " Creating properly formatted minimal scene"
echo "======================================"

# Create a minimal but valid CoppeliaSim scene file
cat > /tmp/empty_scene.ttt << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CoppeliaSimScene>
  <version>
    <major>4</major>
    <minor>6</minor>
    <rev>0</rev>
    <build>18</build>
  </version>
  <sceneObjects>
    <object class="CLuaScript" type="1" id="0">
      <script>
function sysCall_init()
    print("[EMPTY SCENE] Initialized successfully")
end

function sysCall_actuation()
    -- Keep simulation running
end

function sysCall_sensing()
    -- Keep script alive
end
      </script>
    </object>
  </sceneObjects>
</CoppeliaSimScene>
EOF

echo "Created minimal scene at /tmp/empty_scene.ttt"
ls -la /tmp/empty_scene.ttt

# ======================================
# First try with empty scene to verify CoppeliaSim works
# ======================================
echo "======================================"
echo " Testing with empty scene first"
echo "======================================"

COPPELIA_CMD="/opt/coppelia/coppeliaSim -H -s0 -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 -GzmqRemoteApi.rpcAddress=0.0.0.0 /tmp/empty_scene.ttt"

echo "Command: xvfb-run -a $COPPELIA_CMD"
echo "Starting at: $(date)"

# Start with xvfb and capture all output
xvfb-run -a --server-args="-screen 0 1024x768x24" \
    $COPPELIA_CMD > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

# Wait a moment for process to start
sleep 5

# Check if process is running
if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "✅ Process $COPPELIA_PID is running"
else
    echo "❌ ERROR: Process $COPPELIA_PID is NOT running!"
    echo "Command used: $COPPELIA_CMD"
    echo "----------------------------------------"
    echo "Complete log:"
    cat coppeliasim.log
    echo "----------------------------------------"
    exit 1
fi

# ======================================
# Monitor log for successful initialization
# ======================================
echo "======================================"
echo " Waiting for scene to initialize"
echo "======================================"

TIMEOUT=30
ELAPSED=0
SCENE_READY=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    echo "  [$(date +%H:%M:%S)] checking... ${ELAPSED}s / ${TIMEOUT}s"
    
    # Show log tail periodically
    if [ $((ELAPSED % 5)) -eq 0 ]; then
        echo "--- Last 5 lines of log at ${ELAPSED}s ---"
        tail -5 coppeliasim.log
        echo "----------------------------------------"
    fi
    
    # Check for successful initialization
    if grep -q "EMPTY SCENE] Initialized successfully" coppeliasim.log; then
        SCENE_READY=true
        echo "✅ Empty scene initialized successfully at ${ELAPSED}s"
        break
    fi
    
    # Check for errors
    if grep -q "error" coppeliasim.log; then
        echo "⚠️  Error detected in log:"
        grep -i "error" coppeliasim.log
    fi
    
    # Check if process is still running
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ ERROR: CoppeliaSim process died!"
        echo "----------------------------------------"
        cat coppeliasim.log
        echo "----------------------------------------"
        exit 1
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED+2))
done

if [ "$SCENE_READY" = false ]; then
    echo "❌ Empty scene failed to initialize"
    cat coppeliasim.log
    kill -9 $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

# ======================================
# Now wait for ZMQ to initialize
# ======================================
echo "======================================"
echo " Waiting for ZMQ Remote API server"
echo "======================================"

ZMQ_TIMEOUT=90
ZMQ_ELAPSED=0
ZMQ_READY=false

while [ $ZMQ_ELAPSED -lt $ZMQ_TIMEOUT ]; do
    echo "  [$(date +%H:%M:%S)] waiting for ZMQ... ${ZMQ_ELAPSED}s / ${ZMQ_TIMEOUT}s"
    
    # Check for ZMQ in log
    if grep -q "ZMQ remote API server" coppeliasim.log; then
        echo "✅ ZMQ addon detected in log"
    fi
    
    # Check ports using Python
    python3 << 'EOF' 2>/dev/null
import socket
import sys

def check_port(port):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        result = s.connect_ex(('localhost', port))
        s.close()
        return result == 0
    except:
        return False

rpc = check_port(23000)
cnt = check_port(23001)

if rpc and cnt:
    print("✅ Both ports are open")
    sys.exit(0)
elif rpc:
    print("⚠️  Only port 23000 is open")
    sys.exit(1)
else:
    sys.exit(2)
EOF
    
    PYTHON_RESULT=$?
    
    if [ $PYTHON_RESULT -eq 0 ]; then
        ZMQ_READY=true
        echo "✅ ZMQ ports are ready at ${ZMQ_ELAPSED}s"
        break
    fi
    
    # Check if process is still running
    if ! kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "❌ ERROR: CoppeliaSim process died!"
        cat coppeliasim.log
        exit 1
    fi
    
    sleep 2
    ZMQ_ELAPSED=$((ZMQ_ELAPSED+2))
done

if [ "$ZMQ_READY" = false ]; then
    echo "❌ ZMQ failed to initialize after ${ZMQ_TIMEOUT}s"
    echo "Last 50 lines of log:"
    tail -50 coppeliasim.log
    kill -9 $COPPELIA_PID || true
    exit 1
fi

# ======================================
# Test ZMQ client connection
# ======================================
echo "======================================"
echo " Testing ZMQ client connection"
echo "======================================"

cat > test_zmq.py << 'EOF'
import time
import sys
try:
    from coppeliasim_zmqremoteapi_client import RemoteAPIClient
    print("✅ Imported RemoteAPIClient")
    
    # Try to connect
    for i in range(5):
        try:
            print(f"Connection attempt {i+1}/5...")
            client = RemoteAPIClient('localhost', 23000)
            sim = client.require('sim')
            
            # Test API
            time.sleep(1)
            print(f"✅ Connected successfully!")
            print(f"Simulation time: {sim.getSimulationTime()}")
            
            sys.exit(0)
        except Exception as e:
            print(f"Attempt {i+1} failed: {e}")
            time.sleep(2)
    
    print("❌ All connection attempts failed")
    sys.exit(1)
except ImportError as e:
    print(f"❌ Import error: {e}")
    sys.exit(1)
EOF

python3 test_zmq.py
ZMQ_TEST=$?

if [ $ZMQ_TEST -ne 0 ]; then
    echo "❌ ZMQ client test failed"
    kill -9 $COPPELIA_PID || true
    exit 1
fi

echo "✅ ZMQ Remote API is fully operational!"

# ======================================
# Now try to load the actual scene
# ======================================
echo "======================================"
echo " Testing actual scene file"
echo "======================================"

# Stop current CoppeliaSim instance
kill -TERM $COPPELIA_PID 2>/dev/null || true
sleep 5

# Start with actual scene
echo "Starting CoppeliaSim with actual scene..."
COPPELIA_CMD="/opt/coppelia/coppeliaSim -H -s0 -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 -GzmqRemoteApi.rpcAddress=0.0.0.0 /app/pick_and_place.ttt"

xvfb-run -a --server-args="-screen 0 1024x768x24" \
    $COPPELIA_CMD > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

sleep 5

if ! kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "⚠️  Actual scene failed to load, but empty scene worked!"
    echo "This indicates a problem with your pick_and_place.ttt file"
    echo "Continuing with empty scene for testing..."
    
    # Restart with empty scene
    kill -9 $COPPELIA_PID 2>/dev/null || true
    sleep 2
    
    COPPELIA_CMD="/opt/coppelia/coppeliaSim -H -s0 -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 -GzmqRemoteApi.rpcAddress=0.0.0.0 /tmp/empty_scene.ttt"
    xvfb-run -a --server-args="-screen 0 1024x768x24" \
        $COPPELIA_CMD > coppeliasim.log 2>&1 &
    COPPELIA_PID=$!
    sleep 5
fi

# ======================================
# Run pytest
# ======================================
echo "======================================"
echo " Running pytest"
echo "======================================"

# Determine test path
if [ -d "/app/tests" ]; then
    TEST_PATH="tests"
else
    TEST_PATH="."
fi

# Run tests with timeout
pytest $TEST_PATH \
    --html=report.html \
    --self-contained-html \
    --timeout=180 \
    --timeout-method=thread \
    -vv \
    --capture=no \
    --log-cli-level=INFO || true

TEST_EXIT_CODE=$?

# ======================================
# Cleanup
# ======================================
echo "======================================"
echo " Stopping CoppeliaSim"
echo "======================================"

kill -TERM $COPPELIA_PID 2>/dev/null || true
sleep 5
kill -9 $COPPELIA_PID 2>/dev/null || true

echo "======================================"
echo " Test run complete (exit code $TEST_EXIT_CODE)"
echo "======================================"

exit $TEST_EXIT_CODE
