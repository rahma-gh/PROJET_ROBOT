# ÉTAPE 1 : Build de l'environnement
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Installation des dépendances système (CORRIGÉ avec libglib2.0-0)
# Installation des dépendances système (CORRECTION DU NOM LIBSODIUM)
RUN apt-get update && apt-get install -y \
    wget \
    xvfb \
    libgl1-mesa-dev \
    python3-pip \
    libx11-6 \
    libglib2.0-0 \
    libsodium-dev \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    libxcb-xkb1 \
    libxkbcommon-x11-0 \
    libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    wget xvfb libgl1-mesa-dev python3-pip libx11-6 libxcb-icccm4 \
    libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
    libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 \
    && rm -rf /var/lib/apt/lists/*

# Téléchargement et installation de CoppeliaSim
RUN wget https://downloads.coppeliarobotics.com/V4_6_0_rev18/CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04.tar.xz \
    && tar -xvf CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04.tar.xz \
    && mv CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04 /opt/coppelia

WORKDIR /app

# Installation des librairies Python via requirements
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copie de tout le projet
COPY . .

# ÉTAPE 2 & 3 : Lancement Headless et Tests
# On augmente le sleep à 15s pour être sûr que la scène est chargée
# On passe le chemin de la scène direct après l'exécutable, et -s avec un temps (ex: 60000ms = 1min)
# On utilise un script simple pour garder le simulateur actif pendant les tests
CMD xvfb-run --server-args='-screen 0 1024x768x24' /opt/coppelia/coppeliaSim -h /app/pick_and_place.ttt -s 60000 & \
    sleep 15 && \
    export PYTHONPATH=$PYTHONPATH:/app && \
    pytest --html=report.html --self-contained-html tests/ ; \
    pkill -f coppeliaSim