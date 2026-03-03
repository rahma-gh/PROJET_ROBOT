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
RUN wget https://downloads.coppeliarobotics.com/V4_6_0_rev18/CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04.tar.xz \
   && tar -xf CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04.tar.xz \
   && mv CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04 /opt/coppelia \
   && rm CoppeliaSim_Edu_V4_6_0_rev18_Ubuntu22_04.tar.xz

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
# Entrypoint
# ===============================
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]
