FROM ubuntu:22.04

ENV HOME=/home/zoomrec \
    TZ=America/Chicago \
    TERM=xfce4-terminal \
    START_DIR=/start \
    VNC_RESOLUTION=1920x1080 \
    VNC_COL_DEPTH=24 \
    VNC_PW=zoomrec \
    VNC_PORT=5901 \
    NOVNC_PORT=8080 \
    DISPLAY=:1 \
    MYVER=2 \
    DEBUG=FALSE \
    QT_X11_NO_MITSHM=1 \
    DEBIAN_FRONTEND=noninteractive \
    QT_QPA_PLATFORM=xcb \
    QT_PLUGIN_PATH=/opt/zoom/plugins \
    LD_LIBRARY_PATH=/opt/zoom \
    FFMPEG_DEBUG=FALSE \
    VLC_ALLOW_RUN_AS_ROOT=1


RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository universe && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    wget unzip curl gnupg \
    python3 python3-pip python3-opencv \
    python3-tk python3-dev python3-setuptools \
    xvfb x11-apps x11-utils \
    dbus-x11 \
    xauth \
    thunar gvfs gvfs-backends \
    xfce4-terminal \
    libxkbcommon-x11-0 \
    x11-xserver-utils \
    alsa-utils pulseaudio \
    libgl1-mesa-glx libglib2.0-0 \
    xdotool \
    libxcb1 \
    novnc \
    websockify \
    gnome-screenshot \
    libxcb-render0 \
    libxcb-shm0 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-shape0 \
    libxcb-sync1 \
    libxcb-xfixes0 \
    libxcb-xinerama0 \
    libxcb-xkb1 \
    libglu1-mesa \
    libxrender1 \
    libxi6 \
    libsm6 \
    libice6 \
    libgtk-3-0 \
    libnss3 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libxtst6 \
    libatk1.0-0 \
    libxss1 \
    libasound2 \
    fonts-dejavu-core \
    pavucontrol \
    ffmpeg \
    libavcodec-extra \
    scrot \
    vlc \
    x11vnc \
    openbox \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


# Install pulseaudio
#RUN apt-get update && apt-get install -y \
#    pulseaudio \
#    pavucontrol && \
#    rm -rf /var/lib/apt/lists/*

# Install Zoom (latest)
RUN wget -O zoom.deb https://zoom.us/client/latest/zoom_amd64.deb && \
    apt-get update && apt-get install -y ./zoom.deb && rm zoom.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ADD res/requirements.txt ${HOME}/res/requirements.txt

# Install FFmpeg
#RUN apt-get update && apt-get install --no-install-recommends -y \
#    ffmpeg \
#    libavcodec-extra \
#    gnome-screenshot \
#    chromium-browser \
#    scrot && \
RUN pip3 install --upgrade --no-cache-dir -r ${HOME}/res/requirements.txt && pip3 install --upgrade --no-cache-dir pynput
    # Install VLC - optional
    #apt-get install --no-install-recommends -y vlc

# Install VNC components
#RUN apt-get update && apt-get install -y \
#    x11vnc \
#    openbox \
#    && rm -rf /var/lib/apt/lists/*


# Install Python packages
#pip3 install pyautogui pyscreeze opencv-python pillow schedule

# Create user
RUN useradd -m zoomrec
# openbox menu
RUN mkdir -p /home/zoomrec/.config/openbox
COPY res/menu.xml /home/zoomrec/.config/openbox/menu.xml
RUN chown -R zoomrec:zoomrec /home/zoomrec/.config

USER zoomrec
WORKDIR ${HOME}
RUN mkdir -p /tmp/pulse
RUN chmod 700 /tmp/pulse
# Allow access to pulseaudio
RUN groupadd -f pulse-access && groupadd -f pulse
RUN adduser zoomrec pulse-access || true


USER zoomrec
# Add home resources
ADD res/home/ ${HOME}/

# Add startup
ADD res/entrypoint.sh ${START_DIR}/entrypoint.sh

# Add python script with resources
ADD zoomrec.py ${HOME}/
ADD res/img ${HOME}/img

ENV DISPLAY=:1
ENV QT_X11_NO_MITSHM=1

# Set permissions
USER 0
RUN chmod a+x ${START_DIR}/entrypoint.sh && \
    chmod -R a+rw ${START_DIR} && \
    chown -R zoomrec:zoomrec ${HOME} && \
    find ${HOME}/ -name '*.sh' -exec chmod -v a+x {} +
    #find ${HOME}/ -name '*.desktop' -exec chmod -v a+x {} +
RUN CONFIG=/home/zoomrec/.config/zoomus.conf \
 && mkdir -p /home/zoomrec/.config \
 && touch "$CONFIG" \
 \
    # If AlwaysShowVideoPreviewDialog=false already exists, do nothing
 && if ! grep -qx 'AlwaysShowVideoPreviewDialog=false' "$CONFIG"; then \
 \
        # If AudioAutoAdjust=false exists, insert after it
        if grep -qx 'AudioAutoAdjust=false' "$CONFIG"; then \
            sed -i '/^AudioAutoAdjust=false$/a AlwaysShowVideoPreviewDialog=false' "$CONFIG"; \
        else \
            # Ensure [General] exists, else add it
            grep -qx '\[General\]' "$CONFIG" || echo '[General]' >> "$CONFIG"; \
            # Append both keys if they don't exist
            if ! grep -qx 'AudioAutoAdjust=false' "$CONFIG"; then echo 'AudioAutoAdjust=false' >> "$CONFIG"; fi; \
            echo 'AlwaysShowVideoPreviewDialog=false' >> "$CONFIG"; \
        fi; \
    fi \
 \
 && chown -R zoomrec:zoomrec /home/zoomrec/.config
EXPOSE 5901
EXPOSE 8080
CMD ${START_DIR}/entrypoint.sh
