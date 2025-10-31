xset s 0 0 &
xset s off &

export DISPLAY=:1

# Start xfce
/usr/bin/startxfce4 --replace > "$HOME"/xfce.log &
sleep 1
