"""What the current desktop session lets WolfClip do: hotkey, placement, auto-paste, source app."""

import os
import shutil
import subprocess

from gi.repository import Gio, GLib

from .i18n import tr

try:
    from .x11 import X11
except Exception:  # pragma: no cover - missing libX11
    X11 = None


class Platform:
    def __init__(self):
        self.wayland = bool(os.environ.get("WAYLAND_DISPLAY")) or os.environ.get("XDG_SESSION_TYPE") == "wayland"
        self.x11 = None
        if X11 and os.environ.get("DISPLAY"):
            try:
                self.x11 = X11()
            except RuntimeError:
                self.x11 = None
        self._app_cache: dict[str, tuple[str | None, str | None]] = {}

    # Capabilities

    @property
    def global_hotkey(self) -> bool:
        """X11 key grabs only see keys on a real X11 session, not inside Wayland."""
        return self.x11 is not None and not self.wayland

    @property
    def can_place(self) -> bool:
        return self.x11 is not None and not self.wayland

    @property
    def paste_backend(self) -> str | None:
        if self.x11 and not self.wayland and self.x11.can_paste:
            return "xtest"
        if self.wayland and shutil.which("wtype"):
            return "wtype"
        if shutil.which("ydotool"):
            return "ydotool"
        return None

    def paste_backend_label(self) -> str:
        return {
            "xtest": tr("через X11 (XTest)", "via X11 (XTest)"),
            "wtype": tr("через wtype", "via wtype"),
            "ydotool": tr("через ydotool", "via ydotool"),
        }.get(self.paste_backend, tr("недоступна — установи wtype или ydotool", "unavailable — install wtype or ydotool"))

    # Source app

    def active_window(self) -> int:
        return self.x11.active_window() if self.x11 else 0

    def source_app(self) -> tuple[str | None, str | None]:
        """(desktop id, display name) of the focused app, best effort."""
        if not self.x11:
            return None, None
        cls = self.x11.window_class(self.x11.active_window())
        if not cls:
            return None, None
        if cls not in self._app_cache:
            self._app_cache[cls] = self._lookup_app(cls)
        return self._app_cache[cls]

    @staticmethod
    def _lookup_app(wm_class: str) -> tuple[str | None, str | None]:
        lowered = wm_class.lower()
        for info in Gio.AppInfo.get_all():
            if not isinstance(info, Gio.DesktopAppInfo):
                continue
            app_id = (info.get_id() or "").removesuffix(".desktop")
            wm = (info.get_startup_wm_class() or "").lower()
            if lowered in (wm, app_id.lower(), app_id.split(".")[-1].lower()):
                return info.get_id(), info.get_name()
        for group in Gio.DesktopAppInfo.search(wm_class):
            if group:
                info = Gio.DesktopAppInfo.new(group[0])
                if info:
                    return info.get_id(), info.get_name()
        return None, wm_class.replace("-", " ").title()

    # Paste

    def paste(self, target_window: int):
        backend = self.paste_backend
        terminal = bool(self.x11 and target_window and self.x11.is_terminal(target_window))
        if backend == "xtest":
            self.x11.activate(target_window)
            GLib.timeout_add(70, lambda: self.x11.send_paste(terminal) and False)
        elif backend == "wtype":
            args = ["wtype", "-M", "ctrl"] + (["-M", "shift"] if terminal else []) + ["-k", "v", "-m", "ctrl"]
            subprocess.Popen(args + (["-m", "shift"] if terminal else []))
        elif backend == "ydotool":
            keys = ["29:1"] + (["42:1"] if terminal else []) + ["47:1", "47:0"] + (["42:0"] if terminal else []) + ["29:0"]
            subprocess.Popen(["ydotool", "key", *keys])


def gnome_shortcut_supported() -> bool:
    return "gnome" in os.environ.get("XDG_CURRENT_DESKTOP", "").lower() and shutil.which("gsettings") is not None


def register_gnome_shortcut(binding: str, command: str = "wolfclip --toggle") -> bool:
    """Adds (or updates) a GNOME custom keyboard shortcut that runs `command`."""
    base = "org.gnome.settings-daemon.plugins.media-keys"
    path = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/wolfclip/"
    try:
        current = subprocess.run(["gsettings", "get", base, "custom-keybindings"],
                                 capture_output=True, text=True, check=True).stdout.strip()
        paths = [] if current.startswith("@as") else [p.strip(" '") for p in current.strip("[]").split(",") if p.strip()]
        if path not in paths:
            paths.append(path)
        subprocess.run(["gsettings", "set", base, "custom-keybindings", str(paths)], check=True)
        schema = f"{base}.custom-keybinding:{path}"
        for key, value in (("name", "WolfClip"), ("command", command), ("binding", binding)):
            subprocess.run(["gsettings", "set", schema, key, value], check=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False
