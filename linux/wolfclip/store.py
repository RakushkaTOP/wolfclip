"""Clipboard history kept in memory and mirrored to ~/.local/share/wolfclip."""

import hashlib
import json
import os
import re
import time
import uuid
from dataclasses import asdict, dataclass, field, fields
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlparse

from gi.repository import GLib

from .i18n import IS_RU, plural, tr

DATA_DIR = Path(
    os.environ.get("WOLFCLIP_DATA_DIR")
    or Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "wolfclip"
)


@dataclass
class ClipItem:
    kind: str  # text | link | color | image | files
    fingerprint: str
    id: str = field(default_factory=lambda: uuid.uuid4().hex)
    text: str | None = None
    html: str | None = None
    image_file: str | None = None
    width: int | None = None
    height: int | None = None
    files: list[str] | None = None  # file:// URIs
    chars: int | None = None
    lines: int | None = None
    app_id: str | None = None  # desktop file id of the source app
    app_name: str | None = None
    date: float = field(default_factory=time.time)
    pinned: bool = False

    @property
    def paths(self) -> list[str]:
        return [unquote(urlparse(u).path) for u in self.files or []]

    def search_text(self) -> str:
        app = self.app_name or ""
        if self.kind == "files":
            return " ".join(os.path.basename(p) for p in self.paths) + " " + app
        if self.kind == "image":
            return "картинка изображение скриншот image picture screenshot " + app
        return (self.text or "")[:20000] + " " + app


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


_COLOR = re.compile(r"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")


def classify(text: str) -> str:
    t = text.strip()
    if len(t) <= 9 and _COLOR.match(t):
        return "color"
    if len(t) < 4096 and not any(c.isspace() for c in t):
        u = urlparse(t)
        if u.scheme in ("http", "https") and u.netloc:
            return "link"
    return "text"


def color_rgba(hex_text: str) -> tuple[int, int, int, int] | None:
    s = hex_text.strip().lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) not in (6, 8):
        return None
    try:
        v = int(s, 16)
    except ValueError:
        return None
    if len(s) == 6:
        return (v >> 16) & 255, (v >> 8) & 255, v & 255, 255
    return (v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255


def preview(text: str) -> str:
    """First lines with blank edges and common indentation removed."""
    lines = text[:1200].replace("\r\n", "\n").replace("\t", "    ").split("\n")
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    indents = [len(line) - len(line.lstrip(" ")) for line in lines if line.strip()]
    common = min(indents) if indents else 0
    if common:
        lines = [line[min(common, len(line) - len(line.lstrip(" "))):] for line in lines]
    return "\n".join(lines[:8])


def looks_like_code(text: str) -> bool:
    head = text[:800]
    if "\n" not in head:
        return False
    markers = ["{", "}", ";", "=>", "->", "</", "def ", "func ", "const ", "import ", "return ", "#include", "$ ", "()"]
    hits = sum(m in head for m in markers)
    indented = sum(1 for line in head.split("\n") if line.startswith(("  ", "\t")))
    return hits >= 3 or (hits >= 1 and indented >= 1)


_MONTHS_RU = ["янв.", "февр.", "мар.", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."]
_MONTHS_EN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def relative(ts: float, now: float | None = None) -> str:
    now = now or time.time()
    s = now - ts
    d, today = datetime.fromtimestamp(ts), datetime.fromtimestamp(now)
    if s < 45:
        return tr("только что", "just now")
    if s < 3600:
        return tr(f"{max(1, int(s // 60))} мин назад", f"{max(1, int(s // 60))} min ago")
    if d.date() == today.date():
        return tr(f"{int(s // 3600)} ч назад", f"{int(s // 3600)} h ago")
    if (today.date() - d.date()).days == 1:
        return tr("вчера, ", "yesterday, ") + d.strftime("%H:%M")
    month = (_MONTHS_RU if IS_RU else _MONTHS_EN)[d.month - 1]
    day = f"{d.day} {month}" if IS_RU else f"{month} {d.day}"
    if d.year == today.year:
        return f"{day}, {d.strftime('%H:%M')}"
    return f"{day} {d.year}" if IS_RU else f"{day}, {d.year}"


def detail(item: ClipItem) -> str | None:
    if item.kind == "text":
        if item.lines and item.lines > 8:
            return plural(item.lines, ("строка", "строки", "строк"), ("line", "lines"))
        if item.chars and item.chars > 300:
            return tr(f"{item.chars:,} симв.".replace(",", " "), f"{item.chars:,} chars")
    if item.kind == "image" and item.width and item.height:
        return f"{item.width}×{item.height}"
    return None


class HistoryStore:
    def __init__(self, prefs):
        self.prefs = prefs
        self.items: list[ClipItem] = []
        self.images_dir = DATA_DIR / "images"
        self.images_dir.mkdir(parents=True, exist_ok=True)
        self._path = DATA_DIR / "history.json"
        self._listeners = []
        self._save_source = 0

    def connect(self, listener):
        self._listeners.append(listener)

    def load(self):
        try:
            raw = json.loads(self._path.read_text())
        except FileNotFoundError:
            return
        except (OSError, ValueError) as error:
            print(f"WolfClip: history.json is unreadable, moving it aside: {error}")
            self._path.replace(DATA_DIR / f"history-broken-{int(time.time())}.json")
            return
        known = {f.name for f in fields(ClipItem)}
        self.items = [ClipItem(**{k: v for k, v in entry.items() if k in known}) for entry in raw]
        self._remove_orphan_images()

    # Mutations

    def find(self, fingerprint: str) -> ClipItem | None:
        return next((i for i in self.items if i.fingerprint == fingerprint), None)

    def add(self, item: ClipItem):
        self.items.insert(0, item)
        self.trim()
        self._changed()

    def promote(self, item_id: str, app_id: str | None = None, app_name: str | None = None, keep_source=True):
        for i, item in enumerate(self.items):
            if item.id == item_id:
                self.items.pop(i)
                item.date = time.time()
                if not keep_source:
                    item.app_id, item.app_name = app_id, app_name
                self.items.insert(0, item)
                self._changed()
                return

    def toggle_pin(self, item_id: str):
        for item in self.items:
            if item.id == item_id:
                item.pinned = not item.pinned
        self.trim()
        self._changed()

    def remove(self, item_id: str):
        gone = [i for i in self.items if i.id == item_id]
        self.items = [i for i in self.items if i.id != item_id]
        for item in gone:
            self._delete_files(item)
        self._changed()

    def clear(self):
        """Removes everything except pinned entries."""
        gone = [i for i in self.items if not i.pinned]
        self.items = [i for i in self.items if i.pinned]
        for item in gone:
            self._delete_files(item)
        self._changed()

    def trim(self):
        limit = self.prefs["history_limit"]
        kept, gone, unpinned = [], [], 0
        for item in self.items:
            if item.pinned:
                kept.append(item)
                continue
            unpinned += 1
            (gone if unpinned > limit else kept).append(item)
        if gone:
            self.items = kept
            for item in gone:
                self._delete_files(item)
            self._changed()

    def _changed(self):
        for listener in list(self._listeners):
            listener()
        if self._save_source:
            GLib.source_remove(self._save_source)
        self._save_source = GLib.timeout_add(400, self._save_timeout)

    # Disk

    def _save_timeout(self):
        self._save_source = 0
        self.save_now()
        return False

    def save_now(self):
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        tmp = self._path.with_suffix(".tmp")
        tmp.write_text(json.dumps([asdict(i) for i in self.items], ensure_ascii=False))
        tmp.replace(self._path)

    def image_path(self, item: ClipItem) -> Path | None:
        return self.images_dir / item.image_file if item.image_file else None

    def _delete_files(self, item: ClipItem):
        path = self.image_path(item)
        if path:
            path.unlink(missing_ok=True)

    def _remove_orphan_images(self):
        used = {i.image_file for i in self.items if i.image_file}
        for path in self.images_dir.iterdir():
            if path.name not in used:
                path.unlink(missing_ok=True)

    def disk_usage(self) -> int:
        total = self._path.stat().st_size if self._path.exists() else 0
        return total + sum(p.stat().st_size for p in self.images_dir.iterdir())
