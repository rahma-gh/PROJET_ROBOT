import os
import pytest
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot


@pytest.fixture(scope="module")
def sim():
    client = RemoteAPIClient(host='localhost', port=23000)
    sim = client.require('sim')
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