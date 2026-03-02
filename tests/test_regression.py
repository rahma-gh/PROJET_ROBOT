import pytest
import os
from lib.ArmRobot import UniversalRobot
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

@pytest.fixture(scope="module", autouse=True)
def manage_simulation():
    """Démarre la simulation avant les tests et l'arrête après"""
    try:
        client = RemoteAPIClient()
        sim = client.require('sim')
        
        # On s'assure que la simulation est arrêtée avant de commencer
        sim.stopSimulation()
        import time
        time.sleep(1) 
        
        print("Démarrage de la simulation...")
        sim.startSimulation()
        
        yield sim
        
        print("Arrêt de la simulation...")
        sim.stopSimulation()
    except Exception as e:
        pytest.fail(f"Erreur lors du pilotage de la simulation : {e}")

def test_csv_presence():
    assert os.path.exists('pallet_positions.csv'), "ERREUR : pallet_positions.csv est introuvable !"

def test_load_positions_format():
    from main import LoadPalletPosition
    positions = LoadPalletPosition()
    assert len(positions) > 0, "Le fichier CSV est vide !"
    assert len(positions[0]) == 6

def test_robot_and_scene():
    # Ici, UniversalRobot va utiliser la simulation déjà lancée par la fixture
    robot = UniversalRobot('UR10')
    pos = robot.ReadPosition()
    assert len(pos) == 6
    assert all(isinstance(v, (int, float)) for v in pos)

def test_gripper_init():
    robot = UniversalRobot('UR10')
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None