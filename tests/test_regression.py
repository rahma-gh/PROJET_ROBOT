import os
import pytest
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot


@pytest.fixture(scope="module")
def sim():
    # the CoppeliaSim ZMQ server can take a while to spin up in CI
    client = RemoteAPIClient(host='localhost', port=23000)
    sim = None
    for attempt in range(60):  # wait up to about a minute
        try:
            sim = client.require('sim')
            break
        except Exception as exc:
            # remote api not ready yet, sleep and retry
            print(f"waiting for CoppeliaSim ({attempt+1}/60): {exc}")
            time.sleep(1.0)
    if sim is None:
        pytest.fail("could not connect to CoppeliaSim ZMQ server on localhost:23000")

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