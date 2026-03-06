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
# Start CoppeliaSim with correct arguments
# ======================================
echo "======================================"
echo " Starting CoppeliaSim (headless debug mode)"
echo "======================================"

# Use true headless mode for better compatibility
COPPELIA_CMD="/opt/coppelia/coppeliaSim -H -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 -GzmqRemoteApi.rpcAddress=0.0.0.0 /app/pick_and_place.ttt"

echo "Command: xvfb-run -a $COPPELIA_CMD"
echo "Starting at: $(date)"

# Start with xvfb and capture all output
xvfb-run -a --server-args="-screen 0 1024x768x24" \
    $COPPELIA_CMD > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

# Wait a moment for process to start
sleep 3

# Check if process is running
if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "✅ Process $COPPELIA_PID is running"
else
    echo "❌ ERROR: Process $COPPELIA_PID is NOT running!"
    echo "Command used: $COPPELIA_CMD"
    echo "----------------------------------------"
    echo "First 50 lines of log:"
    head -50 coppeliasim.log 2>/dev/null || echo "Log file not created"
    echo "----------------------------------------"
    exit 1
fi

# ======================================
# Monitor log file for ZMQ startup
# ======================================
echo "======================================"
echo " Monitoring log for ZMQ initialization"
echo "======================================"

TIMEOUT=120
ELAPSED=0
ZMQ_DETECTED=false

# Function to check log
check_log() {
    if [ ! -f coppeliasim.log ]; then
        return 1
    fi
    
    # Look for various ZMQ-related messages
    if grep -q "ZMQ remote API server" coppeliasim.log; then
        echo "✅ ZMQ addon loaded message found"
        return 0
    fi
    return 1
}

# Function to check ports directly with better error handling
check_ports() {
    local rpc_open=false
    local cnt_open=false
    
    # Check RPC port (23000)
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -q ":23000"; then
            echo "✅ Port 23000 is listening (via netstat)"
            rpc_open=true
        fi
    fi
    
    # Check control port (23001)
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -q ":23001"; then
            echo "✅ Port 23001 is listening (via netstat)"
            cnt_open=true
        fi
    fi
    
    # Try Python for both ports if netstat didn't work
    if [ "$rpc_open" = false ] || [ "$cnt_open" = false ]; then
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

if rpc:
    print("Port 23000 is open")
if cnt:
    print("Port 23001 is open")

sys.exit(0 if rpc and cnt else 1)
EOF
        PYTHON_RESULT=$?
        if [ $PYTHON_RESULT -eq 0 ]; then
            rpc_open=true
            cnt_open=true
        fi
    fi
    
    if [ "$rpc_open" = true ] && [ "$cnt_open" = true ]; then
        return 0
    else
        return 1
    fi
}

# Main monitoring loop
while [ $ELAPSED -lt $TIMEOUT ]; do
    echo "  [$(date +%H:%M:%S)] checking... ${ELAPSED}s / ${TIMEOUT}s"
    
    # Show log tail periodically
    if [ $((ELAPSED % 10)) -eq 0 ]; then
        echo "--- Last 10 lines of log at ${ELAPSED}s ---"
        tail -10 coppeliasim.log 2>/dev/null || echo "Log file not ready"
        echo "----------------------------------------"
    fi
    
    # Check for ZMQ in log
    if [ "$ZMQ_DETECTED" = false ] && check_log; then
        ZMQ_DETECTED=true
        echo "✅ ZMQ detected in log at ${ELAPSED}s"
        # Continue to wait for ports
    fi
    
    # Check ports directly
    if check_ports; then
        echo "✅ Both ZMQ ports are open at ${ELAPSED}s"
        break
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

# Final check
if ! check_ports; then
    echo "======================================"
    echo "❌ ERROR: ZMQ ports not fully open after ${TIMEOUT}s"
    echo "======================================"
    
    echo "Complete log file content:"
    echo "--------------------------"
    cat coppeliasim.log
    echo "--------------------------"
    
    # Check listening ports
    echo "Listening ports:"
    netstat -tln 2>/dev/null || ss -tln 2>/dev/null || echo "No port listing tools available"
    
    # Check if process is still running
    if kill -0 $COPPELIA_PID 2>/dev/null; then
        echo "Process $COPPELIA_PID is still running"
        ps aux | grep coppelia
    else
        echo "Process $COPPELIA_PID has terminated"
    fi
    
    kill -9 $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

# ======================================
# Additional wait to ensure ZMQ is fully initialized
# ======================================
echo "======================================"
echo " Waiting for ZMQ to fully initialize..."
echo "======================================"
sleep 5

# ======================================
# Verify ZMQ is fully operational with a client test
# ======================================
echo "======================================"
echo " Testing ZMQ Remote API client connection"
echo "======================================"

# Create Python test script
cat > test_zmq_client.py << 'EOF'
import time
import sys
try:
    from coppeliasim_zmqremoteapi_client import RemoteAPIClient
    print("✅ Imported RemoteAPIClient")
    
    # Try to connect
    print("Attempting to connect to ZMQ Remote API...")
    client = RemoteAPIClient('localhost', 23000)
    sim = client.require('sim')
    
    # Test basic API call
    print("Testing sim.getSimulationTime()...")
    sim_time = sim.getSimulationTime()
    print(f"✅ Success! Simulation time: {sim_time}")
    
    # Test getting object handles
    print("Testing sim.getObject('/')...")
    scene_object = sim.getObject('/')
    print(f"✅ Success! Root object handle: {scene_object}")
    
    print("✅ ZMQ Remote API is fully operational!")
    sys.exit(0)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
EOF

# Run the test
echo "Running ZMQ client test..."
python3 test_zmq_client.py
ZMQ_TEST=$?

if [ $ZMQ_TEST -ne 0 ]; then
    echo "❌ ZMQ client test failed"
    echo "Last 50 lines of log:"
    tail -50 coppeliasim.log
    kill -9 $COPPELIA_PID || true
    exit 1
fi

echo "✅ ZMQ Remote API server is fully operational!"

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
    --log-cli-level=INFO

TEST_EXIT_CODE=$?

# ======================================
# Cleanup
# ======================================
echo "======================================"
echo " Stopping CoppeliaSim"
echo "======================================"

# Graceful shutdown
kill -TERM $COPPELIA_PID 2>/dev/null || true
sleep 5

# Force kill if still running
if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "Force killing CoppeliaSim"
    kill -9 $COPPELIA_PID || true
fi

# ======================================
# Final output
# ======================================
echo "======================================"
echo " Tests finished (exit code $TEST_EXIT_CODE)"
echo "======================================"

echo "Last 50 lines of simulator log:"
echo "--------------------------------"
tail -n 50 coppeliasim.log || true
echo "--------------------------------"

exit $TEST_EXIT_CODE
