FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget unzip curl gnupg \
    python3 python3-pip python3-opencv \
    xvfb x11-apps x11-utils \
    dbus-x11 \
    alsa-utils pulseaudio \
    libgl1-mesa-glx libglib2.0-0 \
    xdotool \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Zoom (latest)
RUN wget -O zoom.deb https://zoom.us/client/latest/zoom_amd64.deb && \
    apt-get update && apt-get install -y ./zoom.deb && rm zoom.deb

# Install Python packages
RUN pip3 install pyautogui pyscreeze opencv-python pillow schedule

# Create user
RUN useradd -m zoomrec
USER zoomrec
WORKDIR /home/zoomrec

ENV DISPLAY=:99
ENV QT_X11_NO_MITSHM=1

COPY zoomrec.py /home/zoomrec/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
