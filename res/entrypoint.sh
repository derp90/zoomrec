#!/bin/bash
set -e

# Fix X Lock
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Start X virtual framebuffer
Xvfb :1 -screen 0 1920x1080x24 &
sleep 2

# Start PulseAudio
pulseaudio --daemonize=no --exit-idle-time=-1 --log-level=error &

# Start D-Bus session
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID

echo "Starting Zoom automation..."
python3 /home/zoomrec/zoomrec.py
