import os
import pytest
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot


@pytest.fixture(scope="module")
def sim():
    """
    Connect to the already-running CoppeliaSim instance.
    The simulation is started by entrypoint.sh before pytest runs,
    so we only call startSimulation() if somehow it stopped.
    """
    client = RemoteAPIClient(host='localhost', port=23000)
    sim = client.require('sim')

    state = sim.getSimulationState()
    print(f"→ Simulation state at fixture setup: {state}")
    if state == 0:
        print("→ Simulation not running — starting it now...")
        sim.startSimulation()
        time.sleep(2.0)

    yield sim

    print("→ Arrêt de la simulation CoppeliaSim...")
    sim.stopSimulation()
    time.sleep(0.5)
    try:
        client.socket.close(linger=0)
        client.context.term()
    except Exception:
        pass


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