#!/bin/bash
set -e

# Fix stale X locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

touch "$HOME/.Xauthority"
chmod 600 "$HOME/.Xauthority"
chown zoomrec:zoomrec "$HOME/.Xauthority"

# Start Xvfb
Xvfb :1 -screen 0 1920x1080x24 &
export DISPLAY=:1
sleep 2

# Setup PulseAudio runtime
export PULSE_RUNTIME_PATH=/tmp/pulse

# allow pulseaudio autospawn
mkdir -p /home/zoomrec/.config/pulse
echo "autospawn = yes" > /home/zoomrec/.config/pulse/client.conf
chown -R zoomrec:zoomrec /home/zoomrec/.config/pulse

echo "Cleaning old PulseAudio temp files..."
rm -rf /tmp/pulse-* /run/pulse

mkdir -p /run/pulse
chown -R zoomrec:zoomrec /run/pulse

echo "Starting PulseAudio as zoomrec..."
su zoomrec -c "
export PULSE_RUNTIME_PATH=/run/pulse
pulseaudio --start --exit-idle-time=-1 --log-level=info
"


# Start a lightweight window manager for VNC visibility
openbox &

# Start x11vnc (no password for now — update later)
x11vnc -display :1 -forever -o /dev/null -nopw -shared -rfbport $VNC_PORT &
/usr/share/novnc/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NOVNC_PORT &

echo "Starting Zoom automation..."
while true; do
    python3 /home/zoomrec/zoomrec.py || echo "Script crashed, restarting in 5s..."
    sleep 5
done
