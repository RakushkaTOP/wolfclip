import os
import sys

# Under Wayland, run through XWayland when it is there: X11 lets WolfClip watch the clipboard
# in the background and place its window; set WOLFCLIP_BACKEND=wayland to opt out.
if os.environ.get("WAYLAND_DISPLAY") and os.environ.get("DISPLAY") and os.environ.get("WOLFCLIP_BACKEND") != "wayland":
    os.environ.setdefault("GDK_BACKEND", "x11")

import gi

try:
    gi.require_version("Gtk", "4.0")
    gi.require_version("Gdk", "4.0")
    gi.require_version("GdkPixbuf", "2.0")
except ValueError:
    sys.exit("WolfClip needs GTK 4 for Python: sudo apt install python3-gi gir1.2-gtk-4.0  (see README)")

try:
    gi.require_version("GdkX11", "4.0")
except ValueError:
    pass

from wolfclip.app import main  # noqa: E402

sys.exit(main())
