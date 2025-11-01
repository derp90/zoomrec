#!/bin/bash
set -e

# Fix stale X locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Xvfb
Xvfb :1 -screen 0 1920x1080x24 &
sleep 2

# PulseAudio runtime
export PULSE_RUNTIME_PATH=/tmp/pulse
rm -rf /tmp/pulse
mkdir -p /tmp/pulse
chmod 700 /tmp/pulse

# Disable autospawn for PA user session
mkdir -p /home/zoomrec/.config/pulse
echo "autospawn = no" > /home/zoomrec/.config/pulse/client.conf
chown -R zoomrec:zoomrec /home/zoomrec/.config/pulse

# Start PulseAudio as user
pulseaudio --daemonize=no --exit-idle-time=-1 --log-level=error &

# No dbus — remove these lines:
# eval $(dbus-launch --sh-syntax)
# export DBUS_SESSION_BUS_ADDRESS
# export DBUS_SESSION_BUS_PID

echo "Starting Zoom automation..."
python3 /home/zoomrec/zoomrec.py
