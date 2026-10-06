#!/usr/bin/env bash
# Installs WolfClip for the current user (no root needed except for missing system packages).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
APP="$DATA/wolfclip/app"
BIN="$HOME/.local/bin"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

has_gtk4() {
  python3 - <<'PY' 2>/dev/null
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk
assert Gtk.get_minor_version() >= 6
PY
}

if ! command -v python3 >/dev/null || ! has_gtk4; then
  if command -v apt-get >/dev/null; then cmd="sudo apt-get install -y python3 python3-gi gir1.2-gtk-4.0 libxtst6 librsvg2-common"
  elif command -v dnf >/dev/null; then cmd="sudo dnf install -y python3 python3-gobject gtk4 libXtst librsvg2"
  elif command -v pacman >/dev/null; then cmd="sudo pacman -S --needed python python-gobject gtk4 libxtst librsvg"
  elif command -v zypper >/dev/null; then cmd="sudo zypper install -y python3 python3-gobject python3-gobject-Gdk typelib-1_0-Gtk-4_0 libXtst6"
  else
    echo "WolfClip needs Python 3 with GTK 4 bindings (PyGObject, GTK >= 4.6). Install them and run this again."
    exit 1
  fi
  bold "WolfClip needs GTK 4 for Python:"
  echo "  $cmd"
  read -r -p "Install now? [Y/n] " answer
  [[ "${answer:-y}" =~ ^[Yy]$ ]] || exit 1
  $cmd
  has_gtk4 || { echo "GTK 4 is still not available to python3."; exit 1; }
fi

"$BIN/wolfclip" --quit >/dev/null 2>&1 || true

mkdir -p "$APP" "$BIN" "$DATA/applications" "$DATA/icons/hicolor/scalable/apps" "$DATA/icons/hicolor/256x256/apps" "$CONFIG/autostart"
rm -rf "$APP/wolfclip"
cp -R "$HERE/wolfclip" "$APP/"
find "$APP" -name '__pycache__' -prune -exec rm -rf {} +

cat > "$BIN/wolfclip" <<SH
#!/bin/sh
PYTHONPATH="$APP\${PYTHONPATH:+:\$PYTHONPATH}" exec python3 -m wolfclip "\$@"
SH
chmod +x "$BIN/wolfclip"

cp "$HERE/wolfclip/icons/wolfclip.svg" "$DATA/icons/hicolor/scalable/apps/wolfclip.svg"
cp "$HERE/wolfclip/icons/wolfclip.png" "$DATA/icons/hicolor/256x256/apps/wolfclip.png"
sed "s|^Exec=.*|Exec=$BIN/wolfclip|" "$HERE/data/wolfclip.desktop" > "$DATA/applications/wolfclip.desktop"
sed -e "s|^Exec=.*|Exec=$BIN/wolfclip|" -e '$a NoDisplay=true' "$HERE/data/wolfclip.desktop" > "$CONFIG/autostart/wolfclip.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$DATA/applications" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$DATA/icons/hicolor" >/dev/null 2>&1 || true

nohup "$BIN/wolfclip" >/dev/null 2>&1 &

bold "WolfClip is installed and running."
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
  echo "Wayland: bind a key to   $BIN/wolfclip --toggle   (WolfClip settings can do it for GNOME)."
  command -v wtype >/dev/null || command -v ydotool >/dev/null || \
    echo "For auto-paste install wtype (wlroots/KDE) or ydotool."
else
  echo "Press Super+V in any app."
fi
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Tip: add $BIN to PATH to run 'wolfclip' from a terminal." ;; esac
