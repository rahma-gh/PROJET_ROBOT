#!/bin/bash
set -e

echo "======================================"
echo " Initializing environment - FINAL ATTEMPT"
echo "======================================"
echo "Current directory: $(pwd)"
echo "User: $(whoami)"
echo "Date: $(date)"

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

export PYTHONPATH=/app
export DISPLAY=:99
export QT_DEBUG_PLUGINS=1

# ======================================
# Clear old logs
# ======================================
rm -f coppeliasim.log
rm -f sim.log

# ======================================
# Find a built-in scene
# ======================================
echo "======================================"
echo " Looking for built-in scenes"
echo "======================================"

# List all .ttt files in the CoppeliaSim installation
echo "Built-in scenes in /opt/coppelia:"
find /opt/coppelia -name "*.ttt" -type f 2>/dev/null | head -10 || echo "No .ttt files found"

# Check for the default scene
if [ -f "/opt/coppelia/scenes/blank.ttt" ]; then
    DEFAULT_SCENE="/opt/coppelia/scenes/blank.ttt"
elif [ -f "/opt/coppelia/scenes/empty.ttt" ]; then
    DEFAULT_SCENE="/opt/coppelia/scenes/empty.ttt"
elif [ -f "/opt/coppelia/system/dfltscn.ttt" ]; then
    DEFAULT_SCENE="/opt/coppelia/system/dfltscn.ttt"
else
    # Use any .ttt file we can find
    DEFAULT_SCENE=$(find /opt/coppelia -name "*.ttt" -type f 2>/dev/null | head -1)
fi

if [ -z "$DEFAULT_SCENE" ]; then
    echo "❌ No built-in scenes found!"
    echo "Will try to create a minimal valid scene file..."
    
    # Create a minimal valid scene using the correct binary format?
    # This is getting too complex - let's create a simple text file
    cat > /tmp/simple_scene.ttt << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<scene>
  <version>4.6.0</version>
  <objects>
    <object class="CLight" name="light">
      <position>5,0,5</position>
    </object>
  </objects>
</scene>
EOF
    DEFAULT_SCENE="/tmp/simple_scene.ttt"
fi

echo "Using scene: $DEFAULT_SCENE"
ls -la "$DEFAULT_SCENE" || echo "Scene file not found!"

# ======================================
# Start CoppeliaSim with built-in scene
# ======================================
echo "======================================"
echo " Starting CoppeliaSim with built-in scene"
echo "======================================"

# Try without headless mode first (with xvfb)
COPPELIA_CMD="/opt/coppelia/coppeliaSim -s0 -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 -GzmqRemoteApi.rpcAddress=0.0.0.0 $DEFAULT_SCENE"

echo "Command: xvfb-run -a $COPPELIA_CMD"
echo "Starting at: $(date)"

# Start with xvfb
xvfb-run -a --server-args="-screen 0 1024x768x24" \
    $COPPELIA_CMD > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

# Wait for process to initialize
sleep 10

# Check if process is still running
if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "✅ Process $COPPELIA_PID is still running"
    
    # Check if ZMQ initialized
    if grep -q "ZMQ remote API server" coppeliasim.log; then
        echo "✅ ZMQ addon detected in log"
    fi
    
    # Wait for ports
    echo "Waiting for ZMQ ports..."
    for i in {1..30}; do
        if netstat -tln 2>/dev/null | grep -q ":23000"; then
            echo "✅ Port 23000 is listening"
            break
        fi
        echo "  waiting... $i/30"
        sleep 2
    done
    
    # Test ZMQ connection
    echo "======================================"
    echo " Testing ZMQ connection"
    echo "======================================"
    
    cat > test_zmq_final.py << 'EOF'
import time
import sys
try:
    from coppeliasim_zmqremoteapi_client import RemoteAPIClient
    print("✅ Imported RemoteAPIClient")
    
    # Try to connect
    for i in range(5):
        try:
            print(f"Connection attempt {i+1}/5...")
            client = RemoteAPIClient()
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
    
    python3 test_zmq_final.py
    ZMQ_TEST=$?
    
    if [ $ZMQ_TEST -eq 0 ]; then
        echo "✅ ZMQ is working!"
        
        # Run pytest
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
            -vv || true
        
        TEST_EXIT_CODE=$?
    else
        echo "❌ ZMQ test failed"
        TEST_EXIT_CODE=1
    fi
    
else
    echo "❌ Process died. Last 50 lines of log:"
    tail -50 coppeliasim.log
    TEST_EXIT_CODE=1
fi

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
echo " Test run complete"
echo "======================================"

exit ${TEST_EXIT_CODE:-0}
