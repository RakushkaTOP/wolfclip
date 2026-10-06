#!/bin/bash
# Copies a few typical things (text, link, color, code, image, file) while the Notes window is focused.
xdotool search --name Notes windowactivate --sync
sleep 0.3
copy() { printf '%s' "$1" | xclip -selection clipboard; sleep 0.5; }
copy "Created the WolfClip repo — Linux build passes on X11."
copy "https://github.com/RakushkaTOP/wolfclip"
copy "#4F8CFF"
copy "def paste(item):
    clipboard.write(item)
    return True"
convert -size 320x180 gradient:'#4f8cff'-'#16181d' /tmp/img.png
xclip -selection clipboard -t image/png -i /tmp/img.png
sleep 0.6
printf 'file:///src/linux/install.sh\r\n' | xclip -selection clipboard -t text/uri-list
sleep 0.6
copy "Привет! Это WolfClip на Linux."
