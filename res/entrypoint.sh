#!/usr/bin/env bash
# resilient entrypoint for zoomrec
set -u  # treat unset vars as errors, but don't exit on command failure (we handle)
[ "${DEBUG:-}" = "True" ] && set -x

LOG="/tmp/entrypoint.log"
ZOOM_LOG="/tmp/zoomrec.log"
START_DIR=${START_DIR:-/start}
DISPLAY=${DISPLAY:-:1}

mkdir -p "$START_DIR" "$HOME/.vnc" /tmp
touch "$LOG" "$ZOOM_LOG"
exec 3>&1 4>&2
# tee both stdout and stderr to log
{
  echo ">>> ENTRYPOINT START $(date)"

  # ensure script CRLF fixed in case it was uploaded from windows
  if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$START_DIR"/entrypoint.sh >/dev/null 2>&1 || true
  fi

  # create vnc passwd (overwrites)
  PASSWD_PATH="$HOME/.vnc/passwd"
  echo "Setting VNC password..."
  echo "${VNC_PW:-zoomrec}" | vncpasswd -f > "$PASSWD_PATH" || echo "vncpasswd failed, continuing"
  chmod 600 "$PASSWD_PATH" || true

  # kill stale X locks (don't fail if not present)
  echo "Cleaning old X locks..."
  vncserver -kill "${DISPLAY}" &>/dev/null || true
  rm -rf /tmp/.X*-lock /tmp/.X11-unix || true

  # Start system dbus if not running
  if [ ! -e /var/run/dbus/pid ]; then
    echo "Starting system dbus..."
    dbus-daemon --system --fork || echo "dbus-daemon system failed (non-fatal)"
  fi

  # Start a session dbus (used by xfce and some apps)
  echo "Starting session dbus..."
  eval "$(dbus-launch --sh-syntax --exit-with-session)" || echo "dbus-launch failed (non-fatal)"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}"
  export DBUS_SESSION_BUS_PID="${DBUS_SESSION_BUS_PID:-}"
  export SESSION_MANAGER="local/$(hostname)/default"
  export XDG_CURRENT_DESKTOP=XFCE
  export DESKTOP_SESSION=xfce

  # Start VNC server
  echo "Starting vncserver on ${DISPLAY}..."
  vncserver "${DISPLAY}" -depth "${VNC_COL_DEPTH:-24}" -geometry "${VNC_RESOLUTION:-1920x1080}" &>> "$LOG" || { echo "vncserver failed - see $LOG"; }

  # Small delay for X to appear
  sleep 2

  # ensure XAUTHORITY points into user's home
  export XAUTHORITY="${HOME}/.Xauthority"
  touch "$XAUTHORITY" || true
  chmod 600 "$XAUTHORITY" || true

  # Start xfce session, but do not use --replace (start fresh)
  echo "Starting xfce4 session..."
  if command -v startxfce4 >/dev/null 2>&1; then
    # run in background and capture logs
    startxfce4 >/tmp/xfce.log 2>&1 &
    echo "xfce started (pid $!)"
  else
    echo "startxfce4 not found, skipping desktop start"
  fi

  sleep 2

  # Start PulseAudio (ignore errors)
  echo "Starting pulseaudio..."
  pulseaudio --daemonize=no --exit-idle-time=-1 --log-level=error &>/dev/null || echo "pulseaudio failed (non-fatal)"

  # Try to create null sinks if pactl exists
  if command -v pactl >/dev/null 2>&1; then
    echo "Configuring pactl sinks..."
    pactl load-module module-null-sink sink_name=speaker >/dev/null 2>&1 || true
    pactl load-module module-null-sink sink_name=microphone >/dev/null 2>&1 || true
    pactl load-module module-loopback latency_msec=1 source=2 sink=microphone >/dev/null 2>&1 || true
    pactl load-module module-remap-source master=microphone.monitor source_name=microphone >/dev/null 2>&1 || true
  else
    echo "pactl not available"
  fi

  # Ensure directories exist for recordings & debug
  mkdir -p "$REC_PATH" "$AUDIO_PATH" "$IMG_PATH" "${DEBUG_PATH:-/tmp}" || true

  echo "Launching zoomrec python directly (no xfce4-terminal)..."
  # run python in background, redirect output to zoom log
  python3 -u "$HOME/zoomrec.py" 2>&1 | tee -a "$ZOOM_LOG" &

  PY_PID=$!
  echo "zoomrec running as pid ${PY_PID}"

  # Keep the container alive and show logs; exit if python dies
  echo "Tailing zoom logs. Press Ctrl+C to stop container."
  tail --pid=${PY_PID} -F "$ZOOM_LOG"
  echo "zoomrec exited, container will stop."
  echo ">>> ENTRYPOINT END $(date)"
} 2>&1 | tee -a "$LOG" >&3
