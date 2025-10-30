#!/bin/bash
set -e
[ "$DEBUG" == "True" ] && set -x

cleanup () {
    kill -s SIGTERM $!
    exit 0
}
trap cleanup SIGINT SIGTERM

mkdir -p "$HOME/.vnc"
PASSWD_PATH="$HOME/.vnc/passwd"
echo "$VNC_PW" | vncpasswd -f > "$PASSWD_PATH"
chmod 600 "$PASSWD_PATH"

# Kill leftover X locks
vncserver -kill "$DISPLAY" &>/dev/null || true
rm -rf /tmp/.X*-lock /tmp/.X11-unix

echo "Starting dbus session..."
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID

export SESSION_MANAGER="local/$(hostname)/default"
export QT_X11_NO_MITSHM=1

echo "Starting VNC server..."
vncserver "$DISPLAY" -depth "$VNC_COL_DEPTH" -geometry "$VNC_RESOLUTION"

echo "Starting XFCE..."
/usr/bin/startxfce4 > "$HOME/xfce.log" 2>&1 &

sleep 4
echo "Starting PulseAudio..."
pulseaudio -D --exit-idle-time=-1 --log-level=error

# Virtual mic setup
pactl load-module module-null-sink sink_name=speaker >/dev/null
pactl set-source-volume 1 100%
pactl load-module module-null-sink sink_name=microphone >/dev/null
pactl set-source-volume 2 100%
pactl load-module module-loopback latency_msec=1 source=2 sink=microphone >/dev/null
pactl load-module module-remap-source master=microphone.monitor source_name=microphone >/dev/null
pactl set-source-volume 3 60%

echo "Launching Zoom recorder..."
sleep 5
python3 -u $HOME/zoomrec.py | tee /tmp/zoomrec.log &

tail -F /tmp/zoomrec.log
