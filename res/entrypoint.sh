#!/bin/bash
set -e

# Start X virtual framebuffer
Xvfb :99 -screen 0 1920x1080x24 &
sleep 2

# Start PulseAudio
pulseaudio --start --log-level=error

# Start D-Bus session
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID

echo "Starting Zoom automation..."
python3 /home/zoomrec/zoomrec.py
