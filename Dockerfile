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
   xvfb \
   libgl1-mesa-dev \
   python3 \
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
   curl \
   net-tools \
   && rm -rf /var/lib/apt/lists/*

# ===============================
# Install CoppeliaSim (V4.7.0)
# ===============================
RUN wget https://downloads.coppeliarobotics.com/V4_7_0_rev4/CoppeliaSim_Edu_V4_7_0_rev4_Ubuntu22_04.tar.xz \
   && tar -xf CoppeliaSim_Edu_V4_7_0_rev4_Ubuntu22_04.tar.xz \
   && mv CoppeliaSim_Edu_V4_7_0_rev4_Ubuntu22_04 /opt/coppelia \
   && rm CoppeliaSim_Edu_V4_7_0_rev4_Ubuntu22_04.tar.xz

ENV COPPELIASIM_ROOT=/opt/coppelia
ENV LD_LIBRARY_PATH=$COPPELIASIM_ROOT:$LD_LIBRARY_PATH
ENV QT_QPA_PLATFORM=offscreen

# ===============================
# Workdir
# ===============================
WORKDIR /app

# ===============================
# Python Dependencies
# ===============================
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# ===============================
# Copy Project
# ===============================
COPY . .

# ===============================
# Setup models and dependencies
# ===============================
RUN mkdir -p /opt/coppelia/models && \
    mkdir -p /app/models

# Create the EfficientConveyor customization model file using printf (more reliable)
RUN printf '%s\n' \
    '-- EfficientConveyor Customization Model (V3)' \
    '-- Auto-generated for Docker compatibility' \
    '' \
    'function getOutletPositions()' \
    '    return {}' \
    'end' \
    '' \
    'function getInletPositions()' \
    '    return {}' \
    'end' \
    '' \
    'function getStackPositions()' \
    '    return {}' \
    'end' \
    '' \
    'function getScaleInfo()' \
    '    return {' \
    '        width = 0.5,' \
    '        depth = 0.5,' \
    '        height = 0.1,' \
    '        mass = 10' \
    '    }' \
    'end' \
    '' \
    'return {' \
    '    getOutletPositions = getOutletPositions,' \
    '    getInletPositions = getInletPositions,' \
    '    getStackPositions = getStackPositions,' \
    '    getScaleInfo = getScaleInfo' \
    '}' \
    > /opt/coppelia/models/efficientconveyor_customization-3.lua

# Verify the file was created
RUN echo "✓ EfficientConveyor customization model created" && \
    ls -la /opt/coppelia/models/

# ===============================
# Make entrypoint executable
# ===============================
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# ===============================
# Default command
# ===============================
CMD ["./entrypoint.sh"]
