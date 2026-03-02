import pytest
import os
from lib.ArmRobot import UniversalRobot

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
    try:
        robot = UniversalRobot('UR10')
        pos = robot.ReadPosition()
        assert len(pos) == 6
    except Exception as e:
        pytest.fail(f"Impossible de se connecter au robot ou à la simulation : {e}")

def test_gripper_init():
    """Vérifie l'attachement de la pince"""
    robot = UniversalRobot('UR10')
    robot.AttachGripper('vacuum_gripper')
    assert robot.gripper is not None, "La pince vacuum_gripper n'a pas pu être initialisée"