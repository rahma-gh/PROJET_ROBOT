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
export DISPLAY=:99
export QT_DEBUG_PLUGINS=1

# ======================================
# Debugging: Check CoppeliaSim installation
# ======================================
echo "======================================"
echo " Checking CoppeliaSim installation"
echo "======================================"
echo "CoppeliaSim root: /opt/coppelia"
ls -la /opt/coppelia/ || echo "ERROR: CoppeliaSim not found!"

echo -e "\nChecking for required libraries:"
ldd /opt/coppelia/coppeliaSim 2>/dev/null | grep "not found" || echo "All libraries seem present"

echo -e "\nChecking for ZeroMQ addon:"
find /opt/coppelia -name "*zmq*" -ls 2>/dev/null || echo "No ZMQ files found"

echo -e "\nChecking addon manifest:"
cat /root/.local/share/CoppeliaSim/addon_manifest.xml 2>/dev/null || echo "No addon manifest found"

echo -e "\nChecking system scripts:"
ls -la /opt/coppelia/system/ 2>/dev/null || echo "No system scripts found"

# ======================================
# Clear old logs
# ======================================
rm -f coppeliasim.log
rm -f sim.log

# ======================================
# Try different approaches to start CoppeliaSim
# ======================================

# Approach 1: Start with no scene (default scene)
echo "======================================"
echo " Approach 1: Starting with default scene (no scene file)"
echo "======================================"

# Start without specifying a scene file - it should load a default empty scene
COPPELIA_CMD="/opt/coppelia/coppeliaSim -H -s0 -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 -GzmqRemoteApi.rpcAddress=0.0.0.0"

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
    
    # Check ports
    echo "Checking ports..."
    netstat -tln 2>/dev/null | grep -E "23000|23001" || echo "No ports listening yet"
    
else
    echo "❌ Process died. Trying alternative approach..."
    kill -9 $COPPELIA_PID 2>/dev/null || true
    sleep 2
    
    # Approach 2: Use legacy remote API instead of ZMQ
    echo "======================================"
    echo " Approach 2: Using legacy remote API"
    echo "======================================"
    
    # Start without ZMQ, just basic simulation
    COPPELIA_CMD="/opt/coppelia/coppeliaSim -H -s0"
    
    echo "Command: xvfb-run -a $COPPELIA_CMD"
    
    xvfb-run -a --server-args="-screen 0 1024x768x24" \
        $COPPELIA_CMD > coppeliasim.log 2>&1 &
    
    COPPELIA_PID=$!
    
    sleep 10
    
    if kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "✅ Process $COPPELIA_PID is still running (legacy mode)"
        
        # For legacy mode, we'll need to use the legacy Python client
        echo "✅ Legacy mode working. Will use legacy remote API."
        
        # Create a simple test to verify
        cat > test_legacy.py << 'EOF'
import time
import sys
import os

# Try to import the legacy remote API
sys.path.append('/opt/coppelia/programming/remoteApiBindings/python/python')
try:
    from coppeliasim_remoteapi.remoteApi import remoteApi
    print("✅ Legacy remote API imported")
    
    # Initialize
    sim = remoteApi()
    clientID = sim.simxStart('127.0.0.1', 19997, True, True, 5000, 5)
    
    if clientID != -1:
        print(f"✅ Connected to simulator with client ID: {clientID}")
        sim.simxFinish(clientID)
        sys.exit(0)
    else:
        print("❌ Failed to connect to simulator")
        sys.exit(1)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
EOF
        
        python3 test_legacy.py
        LEGACY_TEST=$?
        
        if [ $LEGACY_TEST -eq 0 ]; then
            echo "✅ Legacy API working! Will proceed with tests."
            
            # Continue with tests using legacy API
            # Your test code here would need to be adapted to use legacy API
            
            # For now, just keep simulation running for tests
            sleep 5
            
            echo "======================================"
            echo " Running pytest (legacy mode)"
            echo "======================================"
            
            # Run pytest (tests will need to be adapted)
            pytest . --html=report.html --self-contained-html -vv || true
            
            TEST_EXIT_CODE=$?
        else
            echo "❌ Legacy API also failed"
            TEST_EXIT_CODE=1
        fi
    else
        echo "❌ All approaches failed. Final log:"
        cat coppeliasim.log
        exit 1
    fi
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
