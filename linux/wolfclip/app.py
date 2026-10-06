"""Gtk.Application: single instance, command line, actions, theme."""

import sys
from pathlib import Path

from gi.repository import Gdk, Gio, GLib, Gtk

from . import APP_ID, __version__
from .clipboard import ClipboardWatcher
from .i18n import tr
from .platform import Platform
from .prefs import Prefs
from .settings import SettingsWindow, set_autostart
from .store import HistoryStore
from .window import HistoryWindow

HERE = Path(__file__).parent

USAGE = """WolfClip — clipboard history

  wolfclip              start in the background (or open settings if already running)
  wolfclip --toggle     show / hide the history (bind this to a key on Wayland)
  wolfclip --settings   open settings
  wolfclip --quit       quit the running instance
  wolfclip --version
"""


class WolfClipApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.hotkey_taken = False
        self.window = None
        self.settings_window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        if Gdk.Display.get_default() is None:
            print("WolfClip: cannot open a display (run it inside a desktop session)", file=sys.stderr)
            sys.exit(1)
        self.hold()  # keep running without windows
        self.prefs = Prefs()
        self.store = HistoryStore(self.prefs)
        self.store.load()
        self.platform = Platform()
        self.watcher = ClipboardWatcher(self.store, self.prefs, self.platform)
        self._load_css()
        self.window = HistoryWindow(self, self.store, self.prefs, self.platform, self.watcher)
        self.settings_window = SettingsWindow(self, self.store, self.prefs, self.platform)

        for name, callback in (("toggle", lambda *_: self.window.toggle()),
                               ("settings", lambda *_: self.show_settings()),
                               ("clear", lambda *_: self.store.clear()),
                               ("toggle-pause", lambda *_: self.prefs.__setitem__("paused", not self.prefs["paused"])),
                               ("quit", lambda *_: self.quit())):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", callback)
            self.add_action(action)

        self.prefs.connect(self._on_pref)
        self._apply_theme()
        self._register_hotkey()

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        if "--version" in args:
            command_line.print_literal(f"WolfClip {__version__}\n")
        elif "--help" in args or "-h" in args:
            command_line.print_literal(USAGE)
        elif "--quit" in args:
            self.quit()
        elif "--toggle" in args or "--show" in args:
            self.window.toggle()
        elif "--settings" in args or command_line.get_is_remote():
            self.show_settings()
        elif not self.prefs["onboarded"]:
            self.prefs["onboarded"] = True
            set_autostart(True)
            self.show_settings()
        return 0

    def do_shutdown(self):
        self.store.save_now()
        Gtk.Application.do_shutdown(self)

    def show_settings(self):
        self.window.hide_panel()
        self.settings_window.refresh()
        self.settings_window.present()

    # Hotkey / theme

    def _register_hotkey(self):
        if not self.platform.global_hotkey:
            return
        ok, keyval, mods = Gtk.accelerator_parse(self.prefs["hotkey"])
        self.hotkey_taken = not (ok and self.platform.x11.grab(keyval, int(mods), self._on_hotkey))
        if self.hotkey_taken:
            print(f"WolfClip: shortcut {self.prefs['hotkey']} is taken by another app", file=sys.stderr)

    def _on_hotkey(self, timestamp):
        self.window.toggle(timestamp)
        return False

    def _on_pref(self, key, _value):
        if key == "hotkey":
            self._register_hotkey()
            self.settings_window.refresh()
        elif key == "theme":
            self._apply_theme()
        elif key == "history_limit":
            self.store.trim()
        elif key in ("paused", "auto_paste"):
            self.window.refresh_chrome()

    def _apply_theme(self):
        theme = self.prefs["theme"]
        dark = theme == "dark" or (theme == "system" and _system_prefers_dark())
        Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", dark)
        for window in (self.window, self.settings_window):
            window.remove_css_class("dark" if not dark else "light")
            window.add_css_class("dark" if dark else "light")

    @staticmethod
    def _load_css():
        provider = Gtk.CssProvider()
        provider.load_from_path(str(HERE / "style.css"))
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        icons = Gtk.IconTheme.get_for_display(Gdk.Display.get_default())
        icons.add_search_path(str(HERE / "icons"))


def _system_prefers_dark() -> bool:
    source = Gio.SettingsSchemaSource.get_default()
    if source and source.lookup("org.gnome.desktop.interface", True):
        settings = Gio.Settings.new("org.gnome.desktop.interface")
        if "color-scheme" in settings.list_keys() and settings.get_string("color-scheme") == "prefer-dark":
            return True
        if "dark" in settings.get_string("gtk-theme").lower():
            return True
    theme = Gtk.Settings.get_default().get_property("gtk-theme-name") or ""
    return "dark" in theme.lower()


def main():
    GLib.set_application_name("WolfClip")
    return WolfClipApp().run(sys.argv)
