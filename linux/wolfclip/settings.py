"""Settings window."""

import os
import shutil
from pathlib import Path

from gi.repository import Gdk, GLib, GObject, Gtk

from . import __version__
from .i18n import plural, tr
from .platform import gnome_shortcut_supported, register_gnome_shortcut
from .prefs import HOTKEYS, LIMITS, POSITIONS, THEMES, hotkey_label

AUTOSTART = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "autostart" / "wolfclip.desktop"
AUTOSTART_ENTRY = """[Desktop Entry]
Type=Application
Name=WolfClip
Comment=Clipboard history
Exec={exec}
Icon=wolfclip
X-GNOME-Autostart-enabled=true
NoDisplay=true
"""


def launcher() -> str:
    return shutil.which("wolfclip") or str(Path.home() / ".local/bin/wolfclip")


def set_autostart(on: bool):
    if on:
        AUTOSTART.parent.mkdir(parents=True, exist_ok=True)
        AUTOSTART.write_text(AUTOSTART_ENTRY.format(exec=launcher()))
    else:
        AUTOSTART.unlink(missing_ok=True)


def _label(text, css=(), **props):
    label = Gtk.Label(label=text, xalign=0, **props)
    for c in css:
        label.add_css_class(c)
    return label


class SettingsWindow(Gtk.Window):
    def __init__(self, app, store, prefs, platform):
        super().__init__(application=app, title="WolfClip")
        self.store, self.prefs, self.platform, self.app = store, prefs, platform, app
        self.add_css_class("wolfclip-settings")
        self.set_default_size(520, 720)
        self.set_hide_on_close(True)

        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=22)
        page.add_css_class("settings-page")

        hero = Gtk.Box(spacing=16)
        hero.append(Gtk.Image(icon_name="wolfclip", pixel_size=64))
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER)
        title = Gtk.Box(spacing=8)
        title.append(_label("WolfClip", css=["title"]))
        title.append(_label(f"v{__version__}", css=["dim", "small"], valign=Gtk.Align.BASELINE))
        texts.append(title)
        self.hero_text = _label("", css=["dim"], wrap=True, max_width_chars=44)
        texts.append(self.hero_text)
        hero.append(texts)
        page.append(hero)

        # General
        rows = []
        if platform.global_hotkey:
            self.hotkey = self._dropdown([label for _a, label in HOTKEYS], [a for a, _l in HOTKEYS].index(prefs["hotkey"])
                                         if prefs["hotkey"] in [a for a, _l in HOTKEYS] else 0,
                                         lambda i: prefs.__setitem__("hotkey", HOTKEYS[i][0]))
            rows.append((tr("Горячая клавиша", "Shortcut"), self.hotkey))
            self.hotkey_taken = _label(tr("Это сочетание занято другим приложением — выбери другое.",
                                          "This shortcut is taken by another app — pick another one."),
                                       css=["warn", "small"], wrap=True)
        rows.append((tr("Тема", "Appearance"), self._dropdown([t for _k, t in THEMES], [k for k, _t in THEMES].index(prefs["theme"]),
                                                             lambda i: prefs.__setitem__("theme", THEMES[i][0]))))
        if platform.can_place:
            rows.append((tr("Где открывать окно", "Window position"),
                         self._dropdown([t for _k, t in POSITIONS], [k for k, _t in POSITIONS].index(prefs["position"]),
                                        lambda i: prefs.__setitem__("position", POSITIONS[i][0]))))
        rows.append((tr("Вставлять сразу после выбора", "Paste immediately after choosing"),
                     self._switch(prefs["auto_paste"], lambda on: prefs.__setitem__("auto_paste", on))))
        self.autostart = self._switch(AUTOSTART.exists(), set_autostart)
        rows.append((tr("Запускать при входе в систему", "Launch at login"), self.autostart))
        general = self._group(tr("Основное", "General"), rows)
        if platform.global_hotkey:
            general.append(self.hotkey_taken)
        page.append(general)

        # Wayland: the desktop owns global shortcuts
        if not platform.global_hotkey:
            page.append(self._wayland_group())

        # History
        self.usage = _label("", css=["dim"])
        self.clear_button = Gtk.Button(label=tr("Очистить историю…", "Clear history…"), halign=Gtk.Align.END)
        self.clear_button.add_css_class("destructive")
        self.clear_button.connect("clicked", self._on_clear)
        page.append(self._group(tr("История", "History"), [
            (tr("Хранить записей", "Items to keep"),
             self._dropdown([str(n) for n in LIMITS], LIMITS.index(prefs["history_limit"]) if prefs["history_limit"] in LIMITS else 2,
                            lambda i: prefs.__setitem__("history_limit", LIMITS[i]))),
            (tr("Сохранять картинки", "Save images"), self._switch(prefs["save_images"], lambda on: prefs.__setitem__("save_images", on))),
            (tr("Сейчас в истории", "Currently in history"), self.usage),
            ("", self.clear_button),
        ]))

        # Auto-paste
        ok = platform.paste_backend is not None
        status = Gtk.Box(spacing=10)
        status.append(Gtk.Image(icon_name="emblem-ok-symbolic" if ok else "dialog-warning-symbolic", css_classes=["ok" if ok else "warn"]))
        status.append(_label(tr("Автовставка ", "Auto-paste ") + platform.paste_backend_label(), wrap=True, hexpand=True))
        group = self._group(tr("Автовставка", "Auto-paste"), [], extra=status)
        group.append(_label(tr("WolfClip сам нажимает Ctrl+V (в терминалах — Ctrl+Shift+V) в приложении, где ты печатаешь. "
                               "Без этого выбранная запись просто копируется в буфер.",
                               "WolfClip presses Ctrl+V (Ctrl+Shift+V in terminals) in the app you are typing in. "
                               "Without it, the chosen item is only copied to the clipboard."), css=["dim", "small", "footnote"], wrap=True))
        page.append(group)

        privacy = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        for icon, text in (("channel-secure-symbolic", tr("Пароли из менеджеров паролей не записываются", "Passwords from password managers are never recorded")),
                           ("drive-harddisk-symbolic", tr("История хранится только на этом компьютере", "History stays on this computer"))):
            line = Gtk.Box(spacing=10)
            line.append(Gtk.Image(icon_name=icon))
            line.append(_label(text, wrap=True))
            privacy.append(line)
        page.append(self._group(tr("Приватность", "Privacy"), [], extra=privacy))

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_child(page)
        self.set_child(scroller)
        self.connect("notify::visible", lambda *_: self.refresh())
        store.connect(lambda: self.get_visible() and self.refresh())
        self.refresh()

    # Pieces

    def _group(self, title, rows, extra=None):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.append(_label(title, css=["group-title"]))
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        card.add_css_class("card")
        for i, (text, control) in enumerate(rows):
            row = Gtk.Box(spacing=12)
            row.add_css_class("card-row")
            if i:
                card.append(Gtk.Separator())
            row.append(_label(text, hexpand=True, wrap=True))
            control.set_valign(Gtk.Align.CENTER)
            row.append(control)
            card.append(row)
        if extra:
            extra.add_css_class("card-row")
            card.append(extra)
        box.append(card)
        return box

    @staticmethod
    def _dropdown(labels, selected, on_change):
        dropdown = Gtk.DropDown.new_from_strings(labels)
        dropdown.set_selected(max(0, selected))
        dropdown.connect("notify::selected", lambda d, _p: on_change(d.get_selected()))
        return dropdown

    @staticmethod
    def _switch(active, on_change):
        switch = Gtk.Switch(active=active)
        switch.connect("notify::active", lambda s, _p: on_change(s.get_active()))
        return switch

    def _wayland_group(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.append(_label(tr("На Wayland горячие клавиши назначает система. Назначь сочетание (например Super+V) на команду:",
                             "On Wayland the desktop owns global shortcuts. Bind a key (e.g. Super+V) to this command:"),
                          wrap=True))
        command = Gtk.Box(spacing=8)
        code = _label("wolfclip --toggle", css=["mono", "code"], hexpand=True, selectable=True)
        command.append(code)
        copy = Gtk.Button(label=tr("Скопировать", "Copy"))
        copy.connect("clicked", lambda *_: self.get_clipboard().set_content(
            Gdk.ContentProvider.new_for_value(GObject.Value(GObject.TYPE_STRING, "wolfclip --toggle"))))
        command.append(copy)
        box.append(command)
        if gnome_shortcut_supported():
            self.gnome_button = Gtk.Button(label=tr("Назначить Super+V в GNOME", "Set Super+V in GNOME"), halign=Gtk.Align.START)
            self.gnome_button.add_css_class("suggested-action")
            self.gnome_button.connect("clicked", self._on_gnome_shortcut)
            box.append(self.gnome_button)
        return self._group(tr("Горячая клавиша", "Shortcut"), [], extra=box)

    def _on_gnome_shortcut(self, button):
        ok = register_gnome_shortcut("<Super>v", f"{launcher()} --toggle")
        button.set_label(tr("Готово — жми Super+V", "Done — press Super+V") if ok else tr("Не получилось — назначь вручную", "Failed — set it manually"))
        button.set_sensitive(False)

    def _on_clear(self, button):
        if getattr(self, "_confirm", False):
            self.store.clear()
            self._reset_clear()
            return
        self._confirm = True
        button.set_label(tr("Нажми ещё раз — закреплённые останутся", "Click again — pinned stay"))
        GLib.timeout_add_seconds(4, self._reset_clear)

    def _reset_clear(self):
        self._confirm = False
        self.clear_button.set_label(tr("Очистить историю…", "Clear history…"))
        return False

    def refresh(self):
        accel = self.prefs["hotkey"] if self.platform.global_hotkey else None
        key = hotkey_label(accel) if accel else tr("свою горячую клавишу", "your shortcut")
        self.hero_text.set_label(tr(f"История буфера обмена. Нажми {key} в любом приложении — и выбери, что вставить.",
                                    f"Clipboard history. Press {key} in any app and pick what to paste."))
        if self.platform.global_hotkey:
            self.hotkey_taken.set_visible(self.app.hotkey_taken)
        if self.autostart.get_active() != AUTOSTART.exists():
            self.autostart.set_active(AUTOSTART.exists())
        count = plural(len(self.store.items), ("запись", "записи", "записей"), ("item", "items"))
        size = GLib.format_size(self.store.disk_usage())
        self.usage.set_label(f"{count} · {size}")
