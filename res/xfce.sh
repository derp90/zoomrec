#!/bin/bash
export DISPLAY=:1

xset -dpms
xset s off
xset s noblank

# XFCE session (not --replace)
startxfce4 &
