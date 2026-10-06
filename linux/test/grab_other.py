"""Simulates another app that already owns Super+V (for the conflict test)."""
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import GLib
from wolfclip.x11 import X11
x = X11()
print("other app grabbed Super+V:", x.grab(0x76, 1 << 26, lambda t: None), flush=True)
GLib.MainLoop().run()
