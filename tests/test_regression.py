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
    wait_for_port(23000, timeout=60)

    client = RemoteAPIClient(host='localhost', port=23000)
    try:
        sim = client.require('sim')
    except Exception as exc:
        pytest.fail(f"could not connect to CoppeliaSim ZMQ API: {exc}")

    print("→ Démarrage de la simulation CoppeliaSim...")
    sim.startSimulation()
    time.sleep(2.0)
    yield sim
    print("→ Arrêt de la simulation CoppeliaSim...")
    sim.stopSimulation()
    time.sleep(0.5)


def test_csv_presence():
    assert os.path.exists('pallet_positions.csv'), "Fichier CSV manquant !"


def test_load_positions_format(sim):
    from main import LoadPalletPosition
    positions = LoadPalletPosition()
    assert len(positions) > 0
    assert len(positions[0]) == 6


def test_robot_and_scene(sim):
    robot = UniversalRobot('UR10')
    pos = robot.ReadPosition()
    assert len(pos) == 6


def test_gripper_init(sim):
    robot = UniversalRobot('UR10')
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None
