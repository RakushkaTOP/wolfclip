"""Watches the clipboard and writes history entries back to it."""

import uuid
from pathlib import Path
from urllib.parse import urlparse

from gi.repository import Gdk, Gio, GLib, GObject

from .store import ClipItem, classify, sha

# Markers password managers put on data that must not be recorded.
IGNORED_MIMES = ("x-kde-passwordManagerHint", "application/x-kde-passwordManagerHint")
FILE_MIMES = ("text/uri-list", "x-special/gnome-copied-files")
RICH_LIMIT = 400_000
IMAGE_LIMIT = 40_000_000


class ClipboardWatcher:
    def __init__(self, store, prefs, platform):
        self.store = store
        self.prefs = prefs
        self.platform = platform
        self.clipboard = Gdk.Display.get_default().get_clipboard()
        self.clipboard.connect("changed", self._on_changed)

    # Recording

    def _on_changed(self, clipboard):
        if self.prefs["paused"] or clipboard.is_local():
            return
        formats = clipboard.get_formats()
        if any(formats.contain_mime_type(m) for m in IGNORED_MIMES):
            return
        source = self.platform.source_app()
        if formats.contain_gtype(Gdk.FileList.__gtype__) or any(formats.contain_mime_type(m) for m in FILE_MIMES):
            clipboard.read_value_async(Gdk.FileList.__gtype__, GLib.PRIORITY_DEFAULT, None, self._on_files, (formats, source))
        elif formats.contain_gtype(GObject.TYPE_STRING) or formats.contain_mime_type("text/plain;charset=utf-8"):
            clipboard.read_text_async(None, self._on_text, (formats, source))
        elif formats.contain_gtype(Gdk.Texture.__gtype__) and self.prefs["save_images"]:
            clipboard.read_texture_async(None, self._on_texture, source)

    def _record(self, fingerprint, source, make):
        existing = self.store.find(fingerprint)
        if existing:
            self.store.promote(existing.id, *source, keep_source=False)
            return
        item = make()
        if item:
            item.app_id, item.app_name = source
            self.store.add(item)

    def _on_files(self, clipboard, result, data):
        formats, source = data
        try:
            files = clipboard.read_value_finish(result).get_files()
        except GLib.Error:
            files = []
        uris = [f.get_uri() for f in files if f.get_path()]
        if not uris:  # e.g. web links offered as text/uri-list: record them as text
            if formats.contain_gtype(GObject.TYPE_STRING):
                clipboard.read_text_async(None, self._on_text, (formats, source))
            return
        fp = "files:" + sha("\n".join(uris).encode())
        paths = "\n".join(f.get_path() for f in files if f.get_path())
        self._record(fp, source, lambda: ClipItem(kind="files", fingerprint=fp, text=paths, files=uris))

    def _on_text(self, clipboard, result, data):
        formats, source = data
        try:
            text = clipboard.read_text_finish(result)
        except GLib.Error:
            return
        if not text or not text.strip():
            if formats.contain_gtype(Gdk.Texture.__gtype__) and self.prefs["save_images"]:
                clipboard.read_texture_async(None, self._on_texture, source)
            return
        fp = "text:" + sha(text.encode())
        if self.store.find(fp):
            self._record(fp, source, lambda: None)
            return
        item = ClipItem(kind=classify(text), fingerprint=fp, text=text, chars=len(text), lines=text.count("\n") + 1)
        if formats.contain_mime_type("text/html"):
            clipboard.read_async(["text/html"], GLib.PRIORITY_DEFAULT, None, self._on_html, (item, source))
        else:
            self._record(fp, source, lambda: item)

    def _on_html(self, clipboard, result, data):
        item, source = data
        try:
            stream, _mime = clipboard.read_finish(result)
        except GLib.Error:
            self._record(item.fingerprint, source, lambda: item)
            return
        sink = Gio.MemoryOutputStream.new_resizable()

        def done(out, res):
            try:
                out.splice_finish(res)
                raw = out.steal_as_bytes().get_data()
                if len(raw) <= RICH_LIMIT:
                    item.html = raw.decode("utf-8", errors="replace")
            except GLib.Error:
                pass
            self._record(item.fingerprint, source, lambda: item)

        flags = Gio.OutputStreamSpliceFlags.CLOSE_SOURCE | Gio.OutputStreamSpliceFlags.CLOSE_TARGET
        sink.splice_async(stream, flags, GLib.PRIORITY_DEFAULT, None, done)

    def _on_texture(self, clipboard, result, source):
        try:
            texture = clipboard.read_texture_finish(result)
        except GLib.Error:
            return
        if not texture:
            return
        png = texture.save_to_png_bytes().get_data()
        if len(png) > IMAGE_LIMIT:
            return
        fp = "image:" + sha(png)

        def make():
            name = uuid.uuid4().hex + ".png"
            (self.store.images_dir / name).write_bytes(png)
            return ClipItem(kind="image", fingerprint=fp, image_file=name,
                            width=texture.get_width(), height=texture.get_height())

        self._record(fp, source, make)

    # Writing

    def write(self, item: ClipItem, plain: bool = False):
        cb = self.clipboard
        if item.kind == "image":
            path = self.store.image_path(item)
            if path and path.exists():
                cb.set_texture(Gdk.Texture.new_from_filename(str(path)))
            return
        if item.kind == "files" and not plain:
            uris = "\r\n".join(item.files or []) + "\r\n"
            gnome = "copy\n" + "\n".join(item.files or [])
            paths = "\n".join(item.paths)
            cb.set_content(Gdk.ContentProvider.new_union([
                Gdk.ContentProvider.new_for_bytes("x-special/gnome-copied-files", GLib.Bytes.new(gnome.encode())),
                Gdk.ContentProvider.new_for_bytes("text/uri-list", GLib.Bytes.new(uris.encode())),
                Gdk.ContentProvider.new_for_value(GObject.Value(GObject.TYPE_STRING, paths)),
            ]))
            return
        text = item.text or ""
        providers = [Gdk.ContentProvider.new_for_value(GObject.Value(GObject.TYPE_STRING, text))]
        if item.html and not plain:
            providers.insert(0, Gdk.ContentProvider.new_for_bytes("text/html", GLib.Bytes.new(item.html.encode())))
        cb.set_content(Gdk.ContentProvider.new_union(providers))


def file_name(uri: str) -> str:
    return Path(urlparse(uri).path).name
