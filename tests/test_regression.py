import pytest
import os
import time
from lib.ArmRobot import UniversalRobot
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

@pytest.fixture(scope="module", autouse=True)
def manage_simulation():
    """Gère le cycle de vie de la simulation pour tous les tests du module"""
    client = None
    try:
        # Connexion initiale
        client = RemoteAPIClient()
        sim = client.require('sim')
        
        print("Démarrage de la simulation...")
        sim.startSimulation()
        
        # Petit temps d'arrêt pour laisser la physique s'initialiser
        time.sleep(2) 
        
        yield sim
        
        print("Arrêt de la simulation...")
        sim.stopSimulation()
    except Exception as e:
        pytest.fail(f"Erreur fatale de simulation : {e}")

def test_csv_presence():
    assert os.path.exists('pallet_positions.csv'), "Fichier CSV manquant !"

def test_load_positions_format():
    from main import LoadPalletPosition
    positions = LoadPalletPosition()
    assert len(positions) > 0
    assert len(positions[0]) == 6

def test_robot_and_scene():
    # L'objet sim est déjà démarré par la fixture
    robot = UniversalRobot('UR10')
    pos = robot.ReadPosition()
    assert len(pos) == 6

def test_gripper_init():
    robot = UniversalRobot('UR10')
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None