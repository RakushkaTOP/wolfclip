#!/bin/bash
# Starts a headless X11 desktop (Xvfb + openbox + compositor) inside the test container.
export DISPLAY=:99 GTK_A11Y=none
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
dbus-daemon --session --fork --print-address > /tmp/dbus.addr
Xvfb :99 -screen 0 1440x900x24 +extension Composite >/tmp/xvfb.log 2>&1 &
sleep 1
mkdir -p ~/.config/gtk-4.0
printf '[Settings]\ngtk-font-name=Inter 10\ngtk-icon-theme-name=Adwaita\n' > ~/.config/gtk-4.0/settings.ini
convert -size 1440x900 gradient:'#3a3f4b'-'#16181d' /tmp/wall.png
feh --bg-fill /tmp/wall.png
openbox >/tmp/openbox.log 2>&1 &
xcompmgr >/tmp/xcompmgr.log 2>&1 &
sleep 1
echo "session up"
