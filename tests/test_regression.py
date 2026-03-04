import os
import pytest
import time
from coppeliasim_zmqremoteapi_client import RemoteAPIClient
from lib.ArmRobot import UniversalRobot   # add this


@pytest.fixture(scope="session")
def remote_api_client():
    """Crée UNE SEULE connexion ZeroMQ pour toute la session de test"""
    client = RemoteAPIClient()
    yield client
    # Optionnel : on peut fermer proprement si besoin
    # del client  # généralement pas nécessaire


@pytest.fixture(scope="module")
def sim(remote_api_client):
    """Démarre / arrête la simulation uniquement pour les tests du module"""
    sim = remote_api_client.require('sim')
    
    print("→ Démarrage de la simulation CoppeliaSim...")
    sim.startSimulation()
    time.sleep(1.8)           # temps pour que la physique se stabilise
    
    yield sim
    
    print("→ Arrêt de la simulation CoppeliaSim...")
    sim.stopSimulation()
    time.sleep(0.5)


# ───────────────────────────────────────────────
# Modifier les tests pour qu’ils demandent le fixture explicitement
# ───────────────────────────────────────────────

def test_csv_presence():
    assert os.path.exists('pallet_positions.csv'), "Fichier CSV manquant !"


def test_load_positions_format(sim):           # ← on demande sim ici
    from main import LoadPalletPosition
    positions = LoadPalletPosition()
    assert len(positions) > 0
    assert len(positions[0]) == 6


def test_robot_and_scene(sim):                 # ← idem
    robot = UniversalRobot('UR10')
    pos = robot.ReadPosition()
    assert len(pos) == 6


def test_gripper_init(sim):                    # ← idem
    robot = UniversalRobot('UR10')
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None