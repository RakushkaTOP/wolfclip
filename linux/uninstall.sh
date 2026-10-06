#!/usr/bin/env bash
# Removes WolfClip. History stays in ~/.local/share/wolfclip unless you pass --purge.
set -euo pipefail
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
"$HOME/.local/bin/wolfclip" --quit >/dev/null 2>&1 || true
rm -rf "$DATA/wolfclip/app"
rm -f "$HOME/.local/bin/wolfclip" "$DATA/applications/wolfclip.desktop" \
      "$DATA/icons/hicolor/scalable/apps/wolfclip.svg" "$DATA/icons/hicolor/256x256/apps/wolfclip.png" "$CONFIG/autostart/wolfclip.desktop"
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$DATA/wolfclip" "$CONFIG/wolfclip"
fi
echo "WolfClip removed."
