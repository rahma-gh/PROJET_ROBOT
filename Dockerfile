# ===============================
# Base Image
# ===============================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ===============================
# System Dependencies
# ===============================
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    xvfb \
    net-tools \
    netcat \
    python3 \
    python3-pip \
    python-is-python3 \
    libgl1 \
    libglu1-mesa \
    libgl1-mesa-dev \
    libxrender1 \
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
    nano \
    vim \
    && rm -rf /var/lib/apt/lists/*

# ===============================
# Install CoppeliaSim
# ===============================
RUN wget --no-check-certificate https://downloads.coppeliarobotics.com/V4_6_0_rev18/CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04.tar.xz \
    && tar -xf CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04.tar.xz \
    && mv CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04 /opt/coppelia \
    && rm CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04.tar.xz

# ===============================
# Configure CoppeliaSim for headless operation
# ===============================
# Create addon manifest to auto-load ZeroMQ
RUN mkdir -p /root/.local/share/CoppeliaSim/ && \
    echo '<?xml version="1.0" encoding="UTF-8" ?>' > /root/.local/share/CoppeliaSim/addon_manifest.xml && \
    echo '<addons>' >> /root/.local/share/CoppeliaSim/addon_manifest.xml && \
    echo '    <addon name="ZeroMQ remote API server" autoload="true" />' >> /root/.local/share/CoppeliaSim/addon_manifest.xml && \
    echo '</addons>' >> /root/.local/share/CoppeliaSim/addon_manifest.xml

# Create system script directory and add startup script
RUN mkdir -p /opt/coppelia/system/
COPY start_zmq.lua /opt/coppelia/system/

# Verify ZeroMQ addon exists
RUN ls -la /opt/coppelia/ && \
    find /opt/coppelia -name "*zmq*" -ls || echo "No ZMQ libraries found"

ENV COPPELIASIM_ROOT=/opt/coppelia
ENV LD_LIBRARY_PATH=$COPPELIASIM_ROOT:$LD_LIBRARY_PATH
ENV QT_QPA_PLATFORM=offscreen
ENV DISPLAY=:99

# ===============================
# Workdir
# ===============================
WORKDIR /app

# ===============================
# Python Dependencies
# ===============================
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt
RUN pip3 install --no-cache-dir coppeliasim-zmqremoteapi-client pytest pytest-html pytest-timeout

# ===============================
# Copy Project
# ===============================
COPY . .

# ===============================
# Entrypoint
# ===============================
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh
RUN chmod +x /app/entrypoint.sh

CMD ["./entrypoint.sh"]
