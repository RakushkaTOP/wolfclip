"""Settings stored as JSON in ~/.config/wolfclip/settings.json."""

import json
import os
from pathlib import Path

from .i18n import tr

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "wolfclip"

# (accelerator in Gtk.accelerator_parse format, label)
HOTKEYS = [
    ("<Super>v", "Super+V"),
    ("<Control><Alt>v", "Ctrl+Alt+V"),
    ("<Super><Shift>v", "Super+Shift+V"),
    ("<Control><Alt>h", "Ctrl+Alt+H"),
]

THEMES = [("dark", tr("Тёмная", "Dark")), ("light", tr("Светлая", "Light")), ("system", tr("Как в системе", "System"))]
POSITIONS = [("mouse", tr("У указателя мыши", "Near the mouse pointer")), ("center", tr("По центру экрана", "Center of the screen"))]
LIMITS = [50, 100, 200, 500, 1000]

DEFAULTS = {
    "hotkey": HOTKEYS[0][0],
    "theme": "dark",
    "position": "mouse",
    "auto_paste": True,
    "history_limit": 200,
    "save_images": True,
    "paused": False,
    "onboarded": False,
}


class Prefs:
    def __init__(self):
        self._path = CONFIG_DIR / "settings.json"
        self._values = dict(DEFAULTS)
        self._listeners = []
        try:
            self._values.update(json.loads(self._path.read_text()))
        except (OSError, ValueError):
            pass

    def __getitem__(self, key):
        return self._values[key]

    def __setitem__(self, key, value):
        if self._values.get(key) == value:
            return
        self._values[key] = value
        self._save()
        for listener in list(self._listeners):
            listener(key, value)

    def connect(self, listener):
        self._listeners.append(listener)

    def _save(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        tmp = self._path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._values, indent=2))
        tmp.replace(self._path)


def hotkey_label(accel: str) -> str:
    return next((label for a, label in HOTKEYS if a == accel), accel)
