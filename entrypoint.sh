#!/bin/bash
set -e

echo "=== Initializing environment ==="

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

echo "=== Starting CoppeliaSim (headless mode) ==="

# Lancement avec :
# -h          → headless
# -q          → quiet (moins de logs)
# -s...       → simulation rapide au démarrage (optionnel)
# -G...       → désactive certains messages de debug ZMQ

xvfb-run --auto-servernum --server-args='-screen 0 1024x768x24' \
  /opt/coppelia/coppeliaSim \
    -h \
    -q \
    -s000000.05 \
    -GzmqRemoteApi.debug=false \
    -GremoteApi.connections=1 \
    /app/pick_and_place.ttt > coppeliasim.log 2>&1 &

COPPELIA_PID=$!

echo "CoppeliaSim launched (PID: $COPPELIA_PID)"
echo "Log redirected to coppeliasim.log"

echo "=== Waiting for ZMQ Remote API server port 23000 ==="

TIMEOUT=90          # secondes max d'attente
INTERVAL=2
ELAPSED=0

until netstat -tuln 2>/dev/null | grep -q ":23000" || [ $ELAPSED -ge $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "  waiting... (${ELAPSED}s / ${TIMEOUT}s)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: CoppeliaSim ZMQ server (port 23000) did not become ready after ${TIMEOUT}s"
    echo "Last lines of coppeliasim.log:"
    tail -n 30 coppeliasim.log
    kill -TERM $COPPELIA_PID 2>/dev/null || true
    exit 1
fi

echo "Simulator ZMQ server is ready (port 23000 open)."

echo "=== Running pytest ==="

# On force l'affichage des logs en temps réel
# et on ajoute un timeout global par test (sécurité)
export PYTHONPATH=/app

pytest tests/ \
    --html=report.html \
    --self-contained-html \
    --timeout=180 \
    --timeout-method=thread \
    -vv || true   # on continue même si échec pour voir le shutdown

TEST_EXIT_CODE=$?

echo "=== Stopping CoppeliaSim ==="

# Envoi SIGTERM puis on attend proprement
kill -TERM $COPPELIA_PID 2>/dev/null || true

# On donne 8 secondes max pour shutdown propre
timeout 8s wait $COPPELIA_PID 2>/dev/null || true

# Si toujours vivant → kill forcé
if kill -0 $COPPELIA_PID 2>/dev/null; then
    echo "CoppeliaSim still running → sending SIGKILL"
    kill -KILL $COPPELIA_PID 2>/dev/null || true
fi

echo "=== Test finished with exit code $TEST_EXIT_CODE ==="

# On affiche les dernières lignes du log CoppeliaSim en cas de debug
echo "Last 20 lines of coppeliasim.log:"
tail -n 20 coppeliasim.log

exit $TEST_EXIT_CODE