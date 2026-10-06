#!/bin/bash
# Captures window geometry WxH+X+Y over black and white wallpapers and rebuilds a transparent PNG.
GEOM=$1; OUT=$2
for bg in black white; do
  convert -size 1440x900 xc:$bg /tmp/$bg.png
  feh --bg-fill /tmp/$bg.png
  pkill xcompmgr; sleep 0.3; (xcompmgr >/dev/null 2>&1 &); sleep 0.8
  import -window root -crop "$GEOM" +repage /tmp/on-$bg.png
done
# alpha = 1 - (white - black); color = black / alpha
convert /tmp/on-white.png /tmp/on-black.png -compose difference -composite -colorspace gray -negate /tmp/alpha.png
convert /tmp/on-black.png /tmp/alpha.png -compose divide_src -composite /tmp/alpha.png -alpha off -compose copy_opacity -composite "$OUT"
echo "matte -> $OUT"
