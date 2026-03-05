import os
import pytest
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot


@pytest.fixture(scope="session")
def remote_api_client():
    """Single ZMQ client reused across the whole test session."""
    client = RemoteAPIClient(host='localhost', port=23000)
    yield client


@pytest.fixture(scope="module")
def sim(remote_api_client):
    """Obtain the sim object and start the simulation once per module."""
    sim = remote_api_client.require('sim')
    print("→ Démarrage de la simulation CoppeliaSim...")
    sim.startSimulation()
    # Give the simulation a moment to settle before tests run
    time.sleep(2.0)
    yield sim
    print("→ Arrêt de la simulation CoppeliaSim...")
    sim.stopSimulation()
    time.sleep(0.5)


# ── Tests ────────────────────────────────────────────────────────────────────

def test_csv_presence():
    assert os.path.exists('pallet_positions.csv'), "Fichier CSV manquant !"


def test_load_positions_format(sim):
    from main import LoadPalletPosition
    positions = LoadPalletPosition()
    assert len(positions) > 0, "Aucune position chargée depuis le CSV"
    assert len(positions[0]) == 6, f"Chaque position doit avoir 6 valeurs, obtenu : {len(positions[0])}"


def test_robot_and_scene(sim):
    robot = UniversalRobot('UR10')
    pos = robot.ReadPosition()
    assert len(pos) == 6, f"ReadPosition() doit retourner 6 valeurs, obtenu : {len(pos)}"


def test_gripper_init(sim):
    robot = UniversalRobot('UR10')
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None, "Le gripper n'a pas été attaché correctement"