"""A plain GTK text field that mirrors its contents to /out/target.txt (paste target for tests)."""
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk

def activate(app):
    win = Gtk.ApplicationWindow(application=app, title="Notes")
    win.set_default_size(640, 360)
    view = Gtk.TextView(top_margin=16, left_margin=16)
    buf = view.get_buffer()
    buf.connect("changed", lambda b: open("/out/target.txt", "w").write(b.get_text(b.get_start_iter(), b.get_end_iter(), False)))
    win.set_child(view)
    win.present()
    view.grab_focus()

app = Gtk.Application(application_id="test.notes")
app.connect("activate", activate)
app.run()
