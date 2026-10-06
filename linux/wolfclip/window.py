"""The history popup: search, filters, list, keyboard navigation."""

import os

from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango

from .clipboard import file_name
from .i18n import plural, tr
from .store import color_rgba, detail, looks_like_code, preview, relative

WIDTH, HEIGHT = 440, 560
MARGIN = 30  # transparent room for the shadow when a compositor is running
MAX_ROWS = 400

FILTERS = [
    ("all", tr("Все", "All"), None),
    ("text", tr("Текст", "Text"), ("text", "color")),
    ("links", tr("Ссылки", "Links"), ("link",)),
    ("images", tr("Картинки", "Images"), ("image",)),
    ("files", tr("Файлы", "Files"), ("files",)),
]


def _label(text="", css=(), xalign=0.0, **props):
    label = Gtk.Label(label=text, xalign=xalign, **props)
    for c in css:
        label.add_css_class(c)
    return label


class HistoryWindow(Gtk.Window):
    def __init__(self, app, store, prefs, platform, watcher):
        super().__init__(application=app, title="WolfClip")
        self.app, self.store, self.prefs, self.platform, self.watcher = app, store, prefs, platform, watcher
        self.query = ""
        self.filter = "all"
        self.visible_items = []
        self.rows = {}
        self.selected_id = None
        self.target_window = 0
        self._was_active = False
        self._thumbs = {}
        self._colors = set()

        self.set_decorated(False)
        self.set_resizable(False)
        self.add_css_class("wolfclip")
        composited = Gdk.Display.get_default().is_composited()
        margin = self.margin = MARGIN if composited else 0
        if not composited:
            self.add_css_class("flat")
        self.set_default_size(WIDTH + 2 * margin, HEIGHT + 2 * margin)

        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        panel.add_css_class("panel")
        panel.set_size_request(WIDTH, HEIGHT)
        panel.set_margin_top(margin)
        panel.set_margin_bottom(margin)
        panel.set_margin_start(margin)
        panel.set_margin_end(margin)
        panel.append(self._build_header())
        panel.append(Gtk.Separator())

        self.listbox = Gtk.ListBox()
        self.listbox.add_css_class("clips")
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.set_activate_on_single_click(True)
        self.listbox.set_header_func(self._header_func)
        self.listbox.connect("row-activated", lambda _lb, row: self.choose(row.item))
        self.scroller = Gtk.ScrolledWindow(vexpand=True)
        self.scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.scroller.set_child(self.listbox)

        self.empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER, vexpand=True)
        self.empty.add_css_class("empty")
        self.empty_icon = Gtk.Image(icon_name="edit-paste-symbolic", pixel_size=36)
        self.empty_title = _label(css=["empty-title"], xalign=0.5)
        self.empty_text = _label(css=["dim"], xalign=0.5, wrap=True, justify=Gtk.Justification.CENTER)
        for w in (self.empty_icon, self.empty_title, self.empty_text):
            self.empty.append(w)

        self.stack = Gtk.Stack(vexpand=True)
        self.stack.add_named(self.scroller, "list")
        self.stack.add_named(self.empty, "empty")
        panel.append(self.stack)

        self.banner = self._build_banner()
        panel.append(self.banner)
        panel.append(Gtk.Separator())
        panel.append(self._build_footer())
        self.set_child(panel)

        keys = Gtk.EventControllerKey()
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)
        self.connect("notify::is-active", self._on_active_changed)
        self.connect("close-request", self._on_close_request)
        store.connect(self._on_store_changed)

    # Building blocks

    def _build_header(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.add_css_class("header")

        top = Gtk.Box(spacing=8)
        top.append(Gtk.Image(icon_name="system-search-symbolic", css_classes=["dim"]))
        self.entry = Gtk.Entry(hexpand=True, placeholder_text=tr("Поиск по истории", "Search history"))
        self.entry.add_css_class("search")
        self.entry.connect("changed", self._on_query_changed)
        top.append(self.entry)
        self.paused_badge = _label(tr("пауза", "paused"), css=["paused"])
        top.append(self.paused_badge)

        menu = Gio.Menu()
        menu.append(tr("Приостановить запись", "Pause recording"), "app.toggle-pause")
        menu.append(tr("Очистить историю…", "Clear history…"), "app.clear")
        section = Gio.Menu()
        section.append(tr("Настройки…", "Settings…"), "app.settings")
        section.append(tr("Выйти из WolfClip", "Quit WolfClip"), "app.quit")
        menu.append_section(None, section)
        button = Gtk.MenuButton(icon_name="view-more-symbolic", menu_model=menu)
        button.add_css_class("flat")
        top.append(button)
        box.append(top)

        chips = Gtk.Box(spacing=6)
        self.chips = {}
        group = None
        for key, title, _kinds in FILTERS:
            chip = Gtk.ToggleButton(label=title)
            chip.add_css_class("chip")
            chip.set_focusable(False)
            if group:
                chip.set_group(group)
            group = group or chip
            chip.connect("toggled", self._on_chip, key)
            chips.append(chip)
            self.chips[key] = chip
        self.chips["all"].set_active(True)
        box.append(chips)
        return box

    def _build_banner(self):
        box = Gtk.Box(spacing=10)
        box.add_css_class("banner")
        box.append(Gtk.Image(icon_name="dialog-warning-symbolic", css_classes=["warn"]))
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1, hexpand=True)
        texts.append(_label(tr("Автовставка недоступна", "Auto-paste is unavailable"), css=["banner-title"]))
        texts.append(_label(tr("Установи wtype или ydotool — пока выбранное только копируется",
                               "Install wtype or ydotool — for now picks are only copied"),
                            css=["dim", "small"], wrap=True))
        box.append(texts)
        return box

    def _build_footer(self):
        box = Gtk.Box(spacing=10)
        box.add_css_class("footer")
        self.paste_hint = self._hint("↵", tr("вставить", "paste"))
        for hint in (self.paste_hint, self._hint("⇧↵", tr("без формата", "plain")),
                     self._hint("Ctrl P", tr("закрепить", "pin")), self._hint("Ctrl Del", tr("удалить", "delete"))):
            box.append(hint)
        return box

    @staticmethod
    def _hint(keys, text):
        box = Gtk.Box(spacing=4)
        box.append(_label(keys, css=["key"]))
        label = _label(text, css=["dim", "small"])
        box.append(label)
        box.label = label
        return box

    # Rows

    def _make_row(self, item, index):
        row = Gtk.ListBoxRow()
        row.item = item
        row.add_css_class("clip")

        body = Gtk.Box(spacing=8)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, hexpand=True)
        content.append(self._content(item))
        content.append(self._meta(item))
        body.append(content)

        trailing = Gtk.Stack(valign=Gtk.Align.START)
        trailing.set_size_request(56, -1)
        idle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, halign=Gtk.Align.END)
        if index < 9:
            idle.append(_label(f"Ctrl {index + 1}", css=["badge"], xalign=1))
        if item.pinned:
            idle.append(Gtk.Image(icon_name="view-pin-symbolic", css_classes=["dim"], halign=Gtk.Align.END, pixel_size=12))
        buttons = Gtk.Box(halign=Gtk.Align.END)
        buttons.append(self._row_button("view-pin-symbolic", tr("Открепить", "Unpin") if item.pinned else tr("Закрепить", "Pin"),
                                        lambda *_: self.toggle_pin(item)))
        buttons.append(self._row_button("user-trash-symbolic", tr("Удалить", "Delete"), lambda *_: self.delete(item)))
        trailing.add_named(idle, "idle")
        trailing.add_named(buttons, "buttons")
        body.append(trailing)
        row.set_child(body)
        row.trailing = trailing

        motion = Gtk.EventControllerMotion()
        motion.connect("enter", lambda *_: trailing.set_visible_child_name("buttons"))
        motion.connect("leave", lambda *_: self._sync_trailing(row))
        row.add_controller(motion)

        click = Gtk.GestureClick(button=3)
        click.connect("pressed", lambda *_: self._row_menu(row))
        row.add_controller(click)
        return row

    @staticmethod
    def _row_button(icon, tooltip, callback):
        button = Gtk.Button(icon_name=icon, tooltip_text=tooltip, valign=Gtk.Align.START)
        button.add_css_class("row-button")
        button.set_focusable(False)
        button.connect("clicked", callback)
        return button

    def _sync_trailing(self, row):
        row.trailing.set_visible_child_name("buttons" if row.item.id == self.selected_id else "idle")

    def _content(self, item):
        kind = item.kind
        if kind == "link":
            url = (item.text or "").strip()
            host = url.split("//", 1)[-1].split("/", 1)[0].removeprefix("www.")
            box = Gtk.Box(spacing=10)
            icon = Gtk.Image.new_from_gicon(Gio.ThemedIcon.new_from_names(["web-browser-symbolic", "insert-link-symbolic"]))
            icon.set_pixel_size(14)
            icon.add_css_class("link-icon")
            box.append(icon)
            texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            texts.append(_label(host, css=["strong"], ellipsize=Pango.EllipsizeMode.END, max_width_chars=34))
            texts.append(_label(url, css=["dim", "small"], ellipsize=Pango.EllipsizeMode.MIDDLE, max_width_chars=40))
            box.append(texts)
            return box
        if kind == "color":
            text = (item.text or "").strip()
            box = Gtk.Box(spacing=10)
            rgba = color_rgba(text) or (0, 0, 0, 0)
            swatch = Gtk.Box()
            swatch.add_css_class("swatch")
            swatch.add_css_class(self._color_class(rgba))
            box.append(swatch)
            box.append(_label(text.upper(), css=["mono", "strong"]))
            return box
        if kind == "image":
            texture = self._thumbnail(item)
            if not texture:
                return _label(tr("Картинка недоступна", "Image unavailable"), css=["dim"])
            w, h = item.width or texture.get_width(), item.height or texture.get_height()
            scale = min(1.0, 300 / max(w, 1), 120 / max(h, 1))
            picture = Gtk.Picture.new_for_paintable(texture)
            picture.set_can_shrink(True)
            picture.set_size_request(max(12, int(w * scale)), max(12, int(h * scale)))
            frame = Gtk.Box(halign=Gtk.Align.START)
            frame.add_css_class("thumb-frame")
            frame.set_overflow(Gtk.Overflow.HIDDEN)
            frame.append(picture)
            return frame
        if kind == "files":
            uris = item.files or []
            box = Gtk.Box(spacing=10)
            box.append(Gtk.Image.new_from_gicon(self._file_icon(uris[0])) if uris else Gtk.Image())
            box.get_first_child().set_pixel_size(30)
            texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            names = ", ".join(file_name(u) for u in uris[:3])
            if len(uris) == 1:
                folder = os.path.dirname(item.paths[0])
                home = os.path.expanduser("~")
                subtitle = "~" + folder[len(home):] if folder.startswith(home) else folder
            else:
                subtitle = plural(len(uris), ("файл", "файла", "файлов"), ("file", "files"))
            texts.append(_label(names, css=["strong"], ellipsize=Pango.EllipsizeMode.MIDDLE, max_width_chars=34))
            texts.append(_label(subtitle, css=["dim", "small"], ellipsize=Pango.EllipsizeMode.MIDDLE, max_width_chars=40))
            box.append(texts)
            return box
        raw = item.text or ""
        label = _label(preview(raw), wrap=True, lines=4, ellipsize=Pango.EllipsizeMode.END, max_width_chars=44)
        label.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        label.add_css_class("mono" if looks_like_code(raw) else "body")
        return label

    def _meta(self, item):
        box = Gtk.Box(spacing=5)
        box.add_css_class("meta")
        if item.app_id:
            info = Gio.DesktopAppInfo.new(item.app_id)
            if info and info.get_icon():
                box.append(Gtk.Image(gicon=info.get_icon(), pixel_size=14))
        parts = [item.app_name or tr("Неизвестно", "Unknown"), relative(item.date)]
        extra = detail(item)
        if extra:
            parts.append(extra)
        box.append(_label("  ·  ".join(parts), css=["dim", "small"], ellipsize=Pango.EllipsizeMode.END))
        return box

    def _color_class(self, rgba):
        """A CSS class painting the swatch; one provider per distinct color."""
        name = "c" + "".join(f"{v:02x}" for v in rgba)
        if name not in self._colors:
            provider = Gtk.CssProvider()
            r, g, b, a = rgba
            css = f".{name} {{ background-color: rgba({r}, {g}, {b}, {a / 255:.3f}); }}"
            if hasattr(provider, "load_from_string"):
                provider.load_from_string(css)
            else:
                provider.load_from_data(css, -1)
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider,
                                                      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
            self._colors.add(name)
        return name

    def _thumbnail(self, item):
        if item.image_file in self._thumbs:
            return self._thumbs[item.image_file]
        path = self.store.image_path(item)
        texture = None
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(path), 600, 240, True)
            texture = Gdk.Texture.new_for_pixbuf(pixbuf)
        except (GLib.Error, TypeError):
            pass
        self._thumbs[item.image_file] = texture
        return texture

    @staticmethod
    def _file_icon(uri):
        try:
            info = Gio.File.new_for_uri(uri).query_info("standard::icon", Gio.FileQueryInfoFlags.NONE, None)
            return info.get_icon()
        except GLib.Error:
            return Gio.ThemedIcon.new("text-x-generic")

    def _header_func(self, row, before):
        title = None
        if row.item.pinned and (before is None):
            title = tr("Закреплённые", "Pinned")
        elif not row.item.pinned and before is not None and before.item.pinned:
            title = tr("Недавние", "Recent")
        row.set_header(_label(title, css=["section"]) if title else None)

    def _row_menu(self, row):
        item = row.item
        menu = Gio.Menu()
        self._menu_item = item
        menu.append(tr("Вставить", "Paste"), "win.paste")
        if item.kind != "image":
            menu.append(tr("Вставить без форматирования", "Paste as plain text"), "win.paste-plain")
        menu.append(tr("Открепить", "Unpin") if item.pinned else tr("Закрепить", "Pin"), "win.pin")
        menu.append(tr("Удалить", "Delete"), "win.delete")
        for name, callback in (("paste", lambda: self.choose(item)), ("paste-plain", lambda: self.choose(item, True)),
                               ("pin", lambda: self.toggle_pin(item)), ("delete", lambda: self.delete(item))):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda *_a, cb=callback: cb())
            self.add_action(action)
        popover = Gtk.PopoverMenu.new_from_model(menu)
        popover.set_parent(row)
        popover.set_has_arrow(False)
        popover.connect("closed", lambda p: GLib.idle_add(p.unparent))
        popover.popup()

    # Data → UI

    def _matches(self, item, query, kinds):
        if kinds and item.kind not in kinds:
            return False
        return not query or query in item.search_text().casefold()

    def rebuild(self, keep_selection=True):
        kinds = next(k for key, _t, k in FILTERS if key == self.filter)
        query = self.query.strip().casefold()
        matched = [i for i in self.store.items if self._matches(i, query, kinds)]
        items = ([i for i in matched if i.pinned] + [i for i in matched if not i.pinned])[:MAX_ROWS]
        self.visible_items = items

        while (child := self.listbox.get_first_child()) is not None:
            self.listbox.remove(child)
        self.rows = {}
        for index, item in enumerate(items):
            row = self._make_row(item, index)
            self.rows[item.id] = row
            self.listbox.append(row)

        if not items:
            searching = bool(query) or self.filter != "all"
            self.empty_icon.set_from_icon_name("system-search-symbolic" if searching else "edit-paste-symbolic")
            self.empty_title.set_label(tr("Ничего не найдено", "Nothing found") if searching else tr("История пуста", "History is empty"))
            self.empty_text.set_label(tr("Попробуй другой запрос или фильтр", "Try another search or filter") if searching
                                      else tr("Скопируй что-нибудь — оно появится здесь", "Copy something — it will show up here"))
            self.stack.set_visible_child_name("empty")
        else:
            self.stack.set_visible_child_name("list")

        if not keep_selection or self.selected_id not in self.rows:
            self.selected_id = items[0].id if items else None
        self._apply_selection(scroll=False)

    def _apply_selection(self, scroll=True):
        row = self.rows.get(self.selected_id)
        if row:
            self.listbox.select_row(row)
        else:
            self.listbox.unselect_all()
        for r in self.rows.values():
            self._sync_trailing(r)
        if row and scroll:
            GLib.idle_add(self._scroll_to, row)

    def _scroll_to(self, row):
        ok, rect = row.compute_bounds(self.listbox)
        if ok:
            adj = self.scroller.get_vadjustment()
            top, bottom = rect.get_y(), rect.get_y() + rect.get_height()
            if row is self.listbox.get_row_at_index(0):
                adj.set_value(0)
            elif top < adj.get_value():
                adj.set_value(top - 24)
            elif bottom > adj.get_value() + adj.get_page_size():
                adj.set_value(bottom - adj.get_page_size() + 4)
        return False

    def _on_store_changed(self):
        if self.get_visible():
            self.rebuild()

    def _on_query_changed(self, entry):
        self.query = entry.get_text()
        self.rebuild(keep_selection=False)

    def _on_chip(self, chip, key):
        if chip.get_active() and self.filter != key:
            self.filter = key
            self.rebuild(keep_selection=False)

    def refresh_chrome(self):
        self.paused_badge.set_visible(self.prefs["paused"])
        self.banner.set_visible(self.prefs["auto_paste"] and self.platform.paste_backend is None)
        self.paste_hint.label.set_label(tr("вставить", "paste") if self.prefs["auto_paste"] else tr("копировать", "copy"))

    # Show / hide

    def toggle(self, timestamp=0):
        if self.get_visible():
            self.hide_panel()
        else:
            self.show_panel(timestamp)

    def show_panel(self, timestamp=0):
        self.target_window = self.platform.active_window()
        self.query = ""
        self.entry.set_text("")
        self.filter = "all"
        self.chips["all"].set_active(True)
        self.refresh_chrome()
        self.rebuild(keep_selection=False)
        self.scroller.get_vadjustment().set_value(0)
        self._was_active = False
        self.present_with_time(timestamp or Gdk.CURRENT_TIME) if hasattr(self, "present_with_time") else self.present()
        if self.platform.can_place:
            # Move right after the map request, before the first frame is drawn; repeat once in case the WM re-placed it.
            Gdk.Display.get_default().flush()
            self._place()
            GLib.timeout_add(40, self._place)
        self.entry.grab_focus()

    def _place(self):
        surface = self.get_surface()
        if surface is None or not hasattr(surface, "get_xid"):
            return False
        x, y = self.platform.x11.pointer()
        display = Gdk.Display.get_default()
        monitor = None
        for i in range(display.get_monitors().get_n_items()):
            m = display.get_monitors().get_item(i)
            g, s = m.get_geometry(), m.get_scale_factor()
            if g.x * s <= x < (g.x + g.width) * s and g.y * s <= y < (g.y + g.height) * s:
                monitor = m
                break
        scale = monitor.get_scale_factor() if monitor else 1
        w, h = self.get_width() * scale or (WIDTH + 2 * MARGIN) * scale, self.get_height() * scale or (HEIGHT + 2 * MARGIN) * scale
        if self.prefs["position"] == "center" and monitor:
            g = monitor.get_geometry()
            px, py = (g.x + g.width / 2) * scale - w / 2, (g.y + g.height / 2) * scale - h / 2
        else:
            px, py = x - (20 + self.margin) * scale, y + (8 - self.margin) * scale
        if monitor:
            g = monitor.get_geometry()
            left, top, right, bottom = g.x * scale, g.y * scale, (g.x + g.width) * scale, (g.y + g.height) * scale
            pad = (8 - self.margin) * scale  # keep the visible panel 8px inside the screen
            if py + h + pad > bottom:
                py = y - h + self.margin * scale - 8 * scale
            px = min(max(px, left + pad), right - w - pad)
            py = min(max(py, top + pad), bottom - h - pad)
        self.platform.x11.move(surface.get_xid(), int(px), int(py))
        return False

    def hide_panel(self):
        self.set_visible(False)

    def _on_active_changed(self, *_):
        if self.is_active():
            self._was_active = True
        elif self._was_active and self.get_visible():
            self.hide_panel()

    def _on_close_request(self, *_):
        self.hide_panel()
        return True

    # Actions

    def choose(self, item, plain=False, paste=True):
        self.watcher.write(item, plain)
        self.store.promote(item.id)
        target = self.target_window
        self.hide_panel()
        if paste and self.prefs["auto_paste"] and self.platform.paste_backend:
            GLib.timeout_add(60, lambda: self.platform.paste(target) and False)

    def toggle_pin(self, item):
        self.selected_id = item.id
        self.store.toggle_pin(item.id)
        self._apply_selection()

    def delete(self, item):
        ids = [i.id for i in self.visible_items]
        if item.id == self.selected_id and item.id in ids:
            i = ids.index(item.id)
            self.selected_id = ids[i + 1] if i + 1 < len(ids) else (ids[i - 1] if i > 0 else None)
        self.store.remove(item.id)

    def move(self, delta):
        ids = [i.id for i in self.visible_items]
        if not ids:
            return
        current = ids.index(self.selected_id) if self.selected_id in ids else 0
        self.selected_id = ids[min(max(current + delta, 0), len(ids) - 1)]
        self._apply_selection()

    def _selected(self):
        return next((i for i in self.visible_items if i.id == self.selected_id), None)

    @staticmethod
    def _latin(keyval, keycode):
        """Shortcut letters by physical key, so Ctrl+P also works on a Cyrillic layout."""
        if keyval < 0x100:
            return Gdk.keyval_to_lower(keyval)
        ok, latin, *_ = Gdk.Display.get_default().translate_key(keycode, Gdk.ModifierType(0), 0)
        return Gdk.keyval_to_lower(latin) if ok else keyval

    def _on_key(self, _controller, keyval, keycode, state):
        ctrl = bool(state & Gdk.ModifierType.CONTROL_MASK)
        shift = bool(state & Gdk.ModifierType.SHIFT_MASK)
        name = Gdk.keyval_name(keyval) or ""
        lower = self._latin(keyval, keycode)

        if name == "Escape":
            if self.entry.get_text():
                self.entry.set_text("")
            else:
                self.hide_panel()
            return True
        if name in ("Down", "KP_Down"):
            self.move(1)
            return True
        if name in ("Up", "KP_Up"):
            self.move(-1)
            return True
        if name in ("Page_Down", "Page_Up"):
            self.move(5 if name == "Page_Down" else -5)
            return True
        if name in ("Return", "KP_Enter"):
            item = self._selected()
            if item:
                self.choose(item, plain=shift)
            return True
        if name in ("Tab", "ISO_Left_Tab"):
            keys = [k for k, _t, _k in FILTERS]
            step = -1 if (shift or name == "ISO_Left_Tab") else 1
            self.chips[keys[(keys.index(self.filter) + step) % len(keys)]].set_active(True)
            return True
        if not ctrl:
            return False
        if Gdk.KEY_1 <= lower <= Gdk.KEY_9:
            n = lower - Gdk.KEY_1
            if n < len(self.visible_items):
                self.choose(self.visible_items[n], plain=shift)
            return True
        item = self._selected()
        if name in ("Delete", "BackSpace", "KP_Delete"):
            if item:
                self.delete(item)
            return True
        if lower == Gdk.KEY_p:
            if item:
                self.toggle_pin(item)
            return True
        if lower == Gdk.KEY_comma:
            self.hide_panel()
            self.app.activate_action("settings", None)
            return True
        if lower == Gdk.KEY_w:
            self.hide_panel()
            return True
        if lower == Gdk.KEY_c and not self.entry.get_selection_bounds():
            if item:
                self.choose(item, paste=False)
            return True
        return False
