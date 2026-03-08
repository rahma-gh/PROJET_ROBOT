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
# Install CoppeliaSim
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
# Create models directory and add missing EfficientConveyor customization
RUN mkdir -p /opt/coppelia/models && \
   mkdir -p /app/models && \
   # Create the missing EfficientConveyor customization model file
   cat > /opt/coppelia/models/efficientconveyor_customization-3.lua << 'EOF'
-- EfficientConveyor Customization Model (V3)
-- Auto-generated for Docker compatibility

function getOutletPositions()
return {}
end

function getInletPositions()
return {}
end

function getStackPositions()
return {}
end

function getScaleInfo()
return {
width = 0.5,
depth = 0.5,
height = 0.1,
mass = 10
}
end

return {
getOutletPositions = getOutletPositions,
getInletPositions = getInletPositions,
getStackPositions = getStackPositions,
getScaleInfo = getScaleInfo
}
EOF
echo "✓ EfficientConveyor customization model created"
# ===============================
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]
