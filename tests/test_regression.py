import pytest
import os
from lib.ArmRobot import UniversalRobot
# On importe le client pour piloter la simulation
from coppeliasim_zmqremoteapi_client import RemoteAPIClient

@pytest.fixture(scope="module", autouse=True)
def manage_simulation():
    """Démarre la simulation avant les tests et l'arrête après"""
    try:
        client = RemoteAPIClient()
        sim = client.require('sim')
        print("Démarrage de la simulation...")
        sim.startSimulation()
        yield sim
        print("Arrêt de la simulation...")
        sim.stopSimulation()
    except Exception as e:
        pytest.fail(f"Erreur lors du pilotage de la simulation : {e}")

def test_csv_presence():
    """Vérifie que le fichier des positions est présent"""
    assert os.path.exists('pallet_positions.csv'), "ERREUR : pallet_positions.csv est introuvable !"

def test_load_positions_format():
    """Vérifie que le CSV peut être lu et contient des données valides"""
    from main import LoadPalletPosition
    positions = LoadPalletPosition()
    assert len(positions) > 0, "Le fichier CSV est vide !"
    assert len(positions[0]) == 6, "Le format des positions doit être [X, Y, Z, Alpha, Beta, Gamma]"

def test_robot_and_scene():
    """Vérifie que le UR10 est accessible dans la simulation"""
    # Pas besoin de try/except ici, pytest s'en occupe
    robot = UniversalRobot('UR10')
    pos = robot.ReadPosition()
    assert len(pos) == 6
    assert all(isinstance(v, (int, float)) for v in pos)

def test_gripper_init():
    """Vérifie l'attachement de la pince"""
    robot = UniversalRobot('UR10')
    # Attention : vérifie bien que le nom dans ta scène est exactement 'vacuum_gripper'
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None, "La pince vacuum_gripper n'a pas pu être initialisée"