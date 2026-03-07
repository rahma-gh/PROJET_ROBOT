import os
import pytest
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot


# helper to wait until the ZMQ port is accepting connections
import socket

def wait_for_port(port, host='localhost', timeout=30):
    """Block until a TCP port can be opened or the timeout expires."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), 1):
                return
        except OSError:
            time.sleep(0.5)
    raise RuntimeError(f"port {port} not reachable after {timeout}s")


@pytest.fixture(scope="module")
def sim():
    # the container entrypoint sets zmqRemoteApi.rpcPort=23000; make sure
    # the server is actually listening before we try to talk to it.  the
    # original test hung indefinitely because ``client.require('sim')``
    # blocked waiting for a reply that never arrived.
    print("\n[DEBUG] Attempting to connect to ZMQ server at localhost:23000")
    wait_for_port(23000, timeout=120)

    print("[DEBUG] Port is open, now creating RemoteAPIClient...")
    client = RemoteAPIClient(host='localhost', port=23000)
    try:
        print("[DEBUG] Requesting sim from RemoteAPIClient...")
        sim = client.require('sim')
        print("[DEBUG] ✓ Successfully got sim object")
    except Exception as exc:
        print(f"[DEBUG] ✗ Failed to get sim: {exc}")
        pytest.fail(f"could not connect to CoppeliaSim ZMQ API: {exc}")

    print("→ Démarrage de la simulation CoppeliaSim...")
    time.sleep(2)  # Extra wait before starting simulation
    sim.startSimulation()
    time.sleep(3.0)  # Increased wait for simulation to stabilize
    yield sim
    print("→ Arrêt de la simulation CoppeliaSim...")
    sim.stopSimulation()
    time.sleep(1.0)  # Increased cleanup time


def test_csv_presence():
    assert os.path.exists('pallet_positions.csv'), "Fichier CSV manquant !"


def test_load_positions_format(sim):
    from main import LoadPalletPosition
    # Just load and verify, no sim needed for CSV parsing
    positions = LoadPalletPosition()
    assert len(positions) > 0
    assert len(positions[0]) == 6


def test_robot_and_scene(sim):
    # Reuse the sim object from fixture instead of creating new client
    robot = UniversalRobot('UR10')
    try:
        pos = robot.ReadPosition()
        assert len(pos) == 6
    finally:
        # Clean up by closing the extra client
        pass


def test_gripper_init(sim):
    # Reuse the sim object from fixture instead of creating new client
    robot = UniversalRobot('UR10')
    try:
        robot.AttachGripper('vacuum_gripper')
        assert robot.gripper is not None
    finally:
        # Clean up by closing the extra client
        pass
