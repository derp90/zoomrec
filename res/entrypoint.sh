#!/bin/bash
set -e

# Fix stale X locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

touch "$HOME/.Xauthority"
chmod 600 "$HOME/.Xauthority"
chown zoomrec:zoomrec "$HOME/.Xauthority"

# Start Xvfb
Xvfb :1 -screen 0 1920x1080x24 &
sleep 2

# Setup PulseAudio runtime
export PULSE_RUNTIME_PATH=/tmp/pulse
rm -rf /tmp/pulse
mkdir -p /tmp/pulse
chmod 700 /tmp/pulse

# Disable autospawn
mkdir -p /home/zoomrec/.config/pulse
echo "autospawn = no" > /home/zoomrec/.config/pulse/client.conf
chown -R zoomrec:zoomrec /home/zoomrec/.config/pulse

# Start PulseAudio
su zoomrec -c "
pulseaudio --start --log-level=info --exit-idle-time=-1 \
  --disallow-exit --disallow-module-loading \
  --system=false --daemonize=yes
"

# Start a lightweight window manager for VNC visibility
openbox &

# Start x11vnc (no password for now — update later)
x11vnc -display :1 -forever -nopw -shared -rfbport 5901 &

echo "Starting Zoom automation..."
python3 /home/zoomrec/zoomrec.py
