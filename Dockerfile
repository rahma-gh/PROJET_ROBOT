FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal dependencies
RUN apt-get update && apt-get install -y \
    wget \
    xvfb \
    libgl1-mesa-dev \
    libglib2.0-0 \
    libx11-6 \
    libsodium-dev \
    python3 \
    python3-pip \
    python3-zmq \
    curl \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Install CoppeliaSim
RUN wget https://downloads.coppeliarobotics.com/V4_7_0_rev4/CoppeliaSim_Edu_V4_7_0_rev4_Ubuntu22_04.tar.xz \
    && tar -xf CoppeliaSim_Edu_V4_7_0_rev4_Ubuntu22_04.tar.xz \
    && mv CoppeliaSim_Edu_V4_7_0_rev4_Ubuntu22_04 /opt/coppelia \
    && rm CoppeliaSim_Edu_V4_7_0_rev4_Ubuntu22_04.tar.xz

# Install Python ZMQ client
RUN pip3 install coppeliasim-zmqremoteapi-client

ENV COPPELIASIM_ROOT=/opt/coppelia
ENV LD_LIBRARY_PATH=$COPPELIASIM_ROOT:$LD_LIBRARY_PATH
ENV QT_QPA_PLATFORM=offscreen

WORKDIR /app

COPY debug_entrypoint.sh .
RUN chmod +x debug_entrypoint.sh

CMD ["./debug_entrypoint.sh"]
