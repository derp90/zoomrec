FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \ 
    HOME=/home/zoomrec \
    TZ=America/Chicago \
    TERM=xfce4-terminal \
    START_DIR=/start \
    DEBIAN_FRONTEND=noninteractive \
    VNC_RESOLUTION=1920x1080 \
    VNC_COL_DEPTH=24 \
    VNC_PW=zoomrec \
    VNC_PORT=5901 \
    DISPLAY=:1 \
    MYVER=2

RUN apt-get update && apt-get install -y \
    wget unzip curl gnupg \
    python3 python3-pip python3-opencv \
    xvfb x11-apps x11-utils \
    dbus-x11 \
    alsa-utils pulseaudio \
    libgl1-mesa-glx libglib2.0-0 \
    xdotool \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install pulseaudio
RUN apt-get install --no-install-recommends -y \
        pulseaudio

RUN apt-get install --no-install-recommends -y \
        pavucontrol
        #pulseaudio \
        #pavucontrol && \
        
# Install firefox
RUN apt-get install --no-install-recommends -y \
        firefox

# Install Zoom (latest)
RUN wget -O zoom.deb https://zoom.us/client/latest/zoom_amd64.deb && \
    apt-get update && apt-get install -y ./zoom.deb && rm zoom.deb

ADD res/requirements.txt ${HOME}/res/requirements.txt

# Install FFmpeg
RUN apt-get install --no-install-recommends -y \
        ffmpeg \
        libavcodec-extra && \
    # Install Python dependencies for script
    apt-get install --no-install-recommends -y \
        python3 \
        python3-pip \
        python3-tk \
        python3-dev \
        python3-setuptools \
        scrot && \
    pip3 install --upgrade --no-cache-dir -r ${HOME}/res/requirements.txt && \
    # Install VLC - optional
    apt-get install --no-install-recommends -y vlc

# Install Python packages
RUN pip3 install pyautogui pyscreeze opencv-python pillow schedule

# Create user
RUN useradd -m zoomrec
USER zoomrec
WORKDIR ${HOME}
# Allow access to pulseaudio
RUN adduser zoomrec pulse-access

USER zoomrec
# Add home resources
ADD res/home/ ${HOME}/

# Add startup
ADD res/entrypoint.sh ${START_DIR}/entrypoint.sh

# Add python script with resources
ADD zoomrec.py ${HOME}/
ADD res/img ${HOME}/img

ENV DISPLAY=:99
ENV QT_X11_NO_MITSHM=1

# Set permissions
USER 0
RUN chmod a+x ${START_DIR}/entrypoint.sh && \
    chmod -R a+rw ${START_DIR} && \
    chown -R zoomrec:zoomrec ${HOME} && \
    find ${HOME}/ -name '*.sh' -exec chmod -v a+x {} +
    #find ${HOME}/ -name '*.desktop' -exec chmod -v a+x {} +

CMD ${START_DIR}/entrypoint.sh
