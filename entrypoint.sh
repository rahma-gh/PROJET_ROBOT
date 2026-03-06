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

# ======================================
# Clear old logs
# ======================================
rm -f coppeliasim.log
rm -f zmq_debug.log

# ======================================
# Start CoppeliaSim with verbose output
# ======================================
echo "======================================"
echo " Starting CoppeliaSim (headless debug mode)"
echo "======================================"

# Command to start CoppeliaSim
COPPELIA_CMD="/opt/coppelia/coppeliaSim -h -GzmqRemoteApi.rpcPort=23000 -GzmqRemoteApi.cntPort=23001 -GzmqRemoteApi.rpcAddress=0.0.0.0 -s /app/pick_and_place.ttt"

echo "Command: xvfb-run -a $COPPELIA_CMD"
echo "Starting at: $(date)"

# Start with xvfb and capture all output
xvfb-run -a --server-args="-screen 0 1024x768x24" \
    $COPPELIA_CMD > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim started with PID: $COPPELIA_PID"
echo "Log file: coppeliasim.log"

# Wait for process to start
sleep 3

# Check if process is running
if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "Process $COPPELIA_PID is running"
else
    echo "ERROR: Process $COPPELIA_PID is NOT running!"
    cat coppeliasim.log
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
    if grep -i -E "zmq|zeromq|remote api" coppeliasim.log > /dev/null; then
        echo "✅ ZMQ-related message found:"
        grep -i -E "zmq|zeromq|remote api" coppeliasim.log | tail -5
        return 0
    fi
    return 1
}

# Function to check ports directly
check_ports() {
    # Try using netstat
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tln | grep -q ":23000"; then
            echo "✅ Port 23000 is listening (via netstat)"
            return 0
        fi
    fi
    
    # Try using ss
    if command -v ss >/dev/null 2>&1; then
        if ss -tln | grep -q ":23000"; then
            echo "✅ Port 23000 is listening (via ss)"
            return 0
        fi
    fi
    
    # Try using Python
    python3 << 'EOF' 2>/dev/null
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
result = s.connect_ex(('localhost', 23000))
s.close()
exit(0 if result == 0 else 1)
EOF
    if [ $? -eq 0 ]; then
        echo "✅ Port 23000 is open (via Python)"
        return 0
    fi
    
    return 1
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
    if check_log; then
        ZMQ_DETECTED=true
        echo "✅ ZMQ detected in log at ${ELAPSED}s"
        break
    fi
    
    # Check ports directly
    if check_ports; then
        ZMQ_DETECTED=true
        echo "✅ ZMQ ports detected at ${ELAPSED}s"
        break
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED+2))
done

# Final check
if [ "$ZMQ_DETECTED" = false ]; then
    echo "======================================"
    echo "❌ ERROR: ZMQ never detected after ${TIMEOUT}s"
    echo "======================================"
    
    echo "Complete log file content:"
    echo "--------------------------"
    cat coppeliasim.log
    echo "--------------------------"
    
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
# Verify ZMQ is fully operational
# ======================================
echo "======================================"
echo " Verifying ZMQ Remote API server"
echo "======================================"

# Create Python test script
cat > test_zmq.py << 'EOF'
import socket
import time
import sys

def test_port(port, timeout=30):
    print(f"Testing port {port}...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2)
            result = s.connect_ex(('localhost', port))
            s.close()
            if result == 0:
                print(f"✅ Port {port} is open")
                return True
        except Exception as e:
            print(f"Error testing port {port}: {e}")
        time.sleep(1)
    print(f"❌ Port {port} never opened")
    return False

if __name__ == "__main__":
    print("Testing ZMQ ports...")
    port1 = test_port(23000)
    port2 = test_port(23001)
    
    if port1 and port2:
        print("✅ Both ZMQ ports are open")
        sys.exit(0)
    else:
        print("❌ ZMQ ports not fully open")
        sys.exit(1)
EOF

# Run the test
echo "Running ZMQ port test..."
python3 test_zmq.py
ZMQ_TEST=$?

if [ $ZMQ_TEST -ne 0 ]; then
    echo "❌ ZMQ port test failed"
    cat coppeliasim.log
    kill -9 $COPPELIA_PID || true
    exit 1
fi

echo "✅ ZMQ Remote API server is ready!"

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

echo "ZMQ debug log (if any):"
cat zmq_debug.log 2>/dev/null || echo "No ZMQ debug log"

exit $TEST_EXIT_CODE
