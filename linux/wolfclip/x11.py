"""Thin ctypes bindings to Xlib/XTest: global hotkey, pointer, active window, synthetic paste.

Uses its own X connection, independent of GTK's, and plugs it into the GLib main loop.
"""

import ctypes
import ctypes.util
import os
import time
from ctypes import CFUNCTYPE, POINTER, Structure, Union, byref, c_char_p, c_int, c_long, c_ubyte, c_uint, c_ulong, c_void_p

from gi.repository import GLib

Window = c_ulong
Atom = c_ulong
KeySym = c_ulong
Time = c_ulong

KeyPress = 2
ClientMessage = 33
GrabModeAsync = 1
ShiftMask, LockMask, ControlMask, Mod1Mask, Mod2Mask, Mod4Mask = 1, 2, 4, 8, 16, 64
SubstructureNotifyMask, SubstructureRedirectMask = 1 << 19, 1 << 20


class XKeyEvent(Structure):
    _fields_ = [
        ("type", c_int), ("serial", c_ulong), ("send_event", c_int), ("display", c_void_p),
        ("window", Window), ("root", Window), ("subwindow", Window), ("time", Time),
        ("x", c_int), ("y", c_int), ("x_root", c_int), ("y_root", c_int),
        ("state", c_uint), ("keycode", c_uint), ("same_screen", c_int),
    ]


class XClientMessageEvent(Structure):
    _fields_ = [
        ("type", c_int), ("serial", c_ulong), ("send_event", c_int), ("display", c_void_p),
        ("window", Window), ("message_type", Atom), ("format", c_int), ("data", c_long * 5),
    ]


class XEvent(Union):
    _fields_ = [("type", c_int), ("xkey", XKeyEvent), ("xclient", XClientMessageEvent), ("pad", c_long * 24)]


class XErrorEvent(Structure):
    _fields_ = [
        ("type", c_int), ("display", c_void_p), ("resourceid", c_ulong), ("serial", c_ulong),
        ("error_code", c_ubyte), ("request_code", c_ubyte), ("minor_code", c_ubyte),
    ]


class XClassHint(Structure):
    _fields_ = [("res_name", c_void_p), ("res_class", c_void_p)]


ErrorHandler = CFUNCTYPE(c_int, c_void_p, POINTER(XErrorEvent))


def _load(name):
    path = ctypes.util.find_library(name)
    try:
        return ctypes.CDLL(path or f"lib{name}.so")
    except OSError:
        return None


_x = _load("X11")
_xtst = _load("Xtst")

if _x:
    _x.XOpenDisplay.argtypes = [c_char_p]
    _x.XOpenDisplay.restype = c_void_p
    _x.XDefaultRootWindow.argtypes = [c_void_p]
    _x.XDefaultRootWindow.restype = Window
    _x.XStringToKeysym.argtypes = [c_char_p]
    _x.XStringToKeysym.restype = KeySym
    _x.XKeysymToKeycode.argtypes = [c_void_p, KeySym]
    _x.XKeysymToKeycode.restype = c_ubyte
    _x.XGrabKey.argtypes = [c_void_p, c_int, c_uint, Window, c_int, c_int, c_int]
    _x.XUngrabKey.argtypes = [c_void_p, c_int, c_uint, Window]
    _x.XSync.argtypes = [c_void_p, c_int]
    _x.XFlush.argtypes = [c_void_p]
    _x.XPending.argtypes = [c_void_p]
    _x.XPending.restype = c_int
    _x.XNextEvent.argtypes = [c_void_p, POINTER(XEvent)]
    _x.XConnectionNumber.argtypes = [c_void_p]
    _x.XConnectionNumber.restype = c_int
    _x.XSetErrorHandler.argtypes = [c_void_p]
    _x.XSetErrorHandler.restype = c_void_p
    _x.XQueryPointer.argtypes = [c_void_p, Window, POINTER(Window), POINTER(Window), POINTER(c_int),
                                 POINTER(c_int), POINTER(c_int), POINTER(c_int), POINTER(c_uint)]
    _x.XInternAtom.argtypes = [c_void_p, c_char_p, c_int]
    _x.XInternAtom.restype = Atom
    _x.XGetWindowProperty.argtypes = [c_void_p, Window, Atom, c_long, c_long, c_int, Atom, POINTER(Atom),
                                      POINTER(c_int), POINTER(c_ulong), POINTER(c_ulong), POINTER(c_void_p)]
    _x.XFree.argtypes = [c_void_p]
    _x.XGetClassHint.argtypes = [c_void_p, Window, POINTER(XClassHint)]
    _x.XSendEvent.argtypes = [c_void_p, Window, c_int, c_long, POINTER(XEvent)]
    _x.XMoveWindow.argtypes = [c_void_p, Window, c_int, c_int]
    _x.XRaiseWindow.argtypes = [c_void_p, Window]

if _xtst:
    _xtst.XTestFakeKeyEvent.argtypes = [c_void_p, c_uint, c_int, c_ulong]


# GDK modifier bits (Gdk.ModifierType) → X modifier masks
_GDK_TO_X = {1 << 0: ShiftMask, 1 << 2: ControlMask, 1 << 3: Mod1Mask, 1 << 26: Mod4Mask, 1 << 28: Mod4Mask}

_TERMINALS = ("terminal", "konsole", "xterm", "kitty", "alacritty", "tilix", "terminator", "wezterm",
              "foot", "urxvt", "rxvt", "st-256color", "guake", "yakuake", "ghostty", "termite", "sakura")


class X11:
    """One Xlib connection for everything WolfClip does outside GTK."""

    def __init__(self):
        self.dpy = _x.XOpenDisplay(None) if _x and os.environ.get("DISPLAY") else None
        if not self.dpy:
            raise RuntimeError("no X display")
        self.root = _x.XDefaultRootWindow(self.dpy)
        self._grab = None
        self._on_hotkey = None
        self._last_press = 0.0
        self._error = False
        self._keep_handler = ErrorHandler(self._record_error)
        channel = GLib.IOChannel.unix_new(_x.XConnectionNumber(self.dpy))
        GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN, self._on_io)

    @property
    def can_paste(self) -> bool:
        return _xtst is not None

    # Hotkey

    def grab(self, keyval: int, gdk_mods: int, on_press) -> bool:
        """Grabs keyval+modifiers on the root window. Returns False if another app owns it."""
        self.ungrab()
        keycode = _x.XKeysymToKeycode(self.dpy, keyval)
        mods = 0
        for gdk_bit, x_bit in _GDK_TO_X.items():
            if gdk_mods & gdk_bit:
                mods |= x_bit
        if not keycode:
            return False
        self._error = False
        previous = _x.XSetErrorHandler(ctypes.cast(self._keep_handler, c_void_p))
        for extra in (0, LockMask, Mod2Mask, LockMask | Mod2Mask):
            _x.XGrabKey(self.dpy, keycode, mods | extra, self.root, 1, GrabModeAsync, GrabModeAsync)
        _x.XSync(self.dpy, 0)
        _x.XSetErrorHandler(previous)
        if self._error:
            self._grab = (keycode, mods)
            self.ungrab()
            return False
        self._grab = (keycode, mods)
        self._on_hotkey = on_press
        return True

    def ungrab(self):
        if self._grab:
            keycode, mods = self._grab
            for extra in (0, LockMask, Mod2Mask, LockMask | Mod2Mask):
                _x.XUngrabKey(self.dpy, keycode, mods | extra, self.root)
            _x.XSync(self.dpy, 0)
        self._grab = None

    def _record_error(self, _dpy, _event):
        self._error = True
        return 0

    def _on_io(self, *_):
        event = XEvent()
        while _x.XPending(self.dpy):
            _x.XNextEvent(self.dpy, byref(event))
            if event.type == KeyPress and self._on_hotkey:
                now = time.monotonic()
                if now - self._last_press > 0.25:  # ignore key auto-repeat
                    self._last_press = now
                    GLib.idle_add(self._on_hotkey, int(event.xkey.time))
        return True

    # Pointer / windows

    def pointer(self) -> tuple[int, int]:
        root, child = Window(), Window()
        rx, ry, wx, wy, mask = c_int(), c_int(), c_int(), c_int(), c_uint()
        _x.XQueryPointer(self.dpy, self.root, byref(root), byref(child), byref(rx), byref(ry),
                         byref(wx), byref(wy), byref(mask))
        return rx.value, ry.value

    def _atom(self, name: str) -> int:
        return _x.XInternAtom(self.dpy, name.encode(), 0)

    def active_window(self) -> int:
        actual, fmt, n, after, data = Atom(), c_int(), c_ulong(), c_ulong(), c_void_p()
        ok = _x.XGetWindowProperty(self.dpy, self.root, self._atom("_NET_ACTIVE_WINDOW"), 0, 1, 0, 33,  # XA_WINDOW
                                   byref(actual), byref(fmt), byref(n), byref(after), byref(data))
        win = 0
        if ok == 0 and data.value:
            if n.value:
                win = ctypes.cast(data, POINTER(c_ulong))[0]
            _x.XFree(data)
        return win

    def window_class(self, win: int) -> str:
        if not win:
            return ""
        hint = XClassHint()
        if not _x.XGetClassHint(self.dpy, win, byref(hint)):
            return ""
        name = ctypes.string_at(hint.res_class).decode(errors="ignore") if hint.res_class else ""
        for ptr in (hint.res_name, hint.res_class):
            if ptr:
                _x.XFree(ptr)
        return name

    def is_terminal(self, win: int) -> bool:
        cls = self.window_class(win).lower()
        return any(t in cls for t in _TERMINALS)

    def activate(self, win: int):
        """Asks the window manager to focus `win` (EWMH _NET_ACTIVE_WINDOW)."""
        if not win:
            return
        event = XEvent()
        event.xclient.type = ClientMessage
        event.xclient.window = win
        event.xclient.message_type = self._atom("_NET_ACTIVE_WINDOW")
        event.xclient.format = 32
        event.xclient.data[0] = 2  # request from a pager-like tool
        _x.XSendEvent(self.dpy, self.root, 0, SubstructureRedirectMask | SubstructureNotifyMask, byref(event))
        _x.XFlush(self.dpy)

    def move(self, xid: int, x: int, y: int):
        _x.XMoveWindow(self.dpy, xid, x, y)
        _x.XRaiseWindow(self.dpy, xid)
        _x.XFlush(self.dpy)

    # Paste

    def send_paste(self, terminal: bool = False):
        """Presses Ctrl+V (Ctrl+Shift+V in terminals) through XTest."""
        keys = ["Control_L"] + (["Shift_L"] if terminal else []) + ["v"]
        codes = [_x.XKeysymToKeycode(self.dpy, _x.XStringToKeysym(k.encode())) for k in keys]
        for code in codes:
            _xtst.XTestFakeKeyEvent(self.dpy, code, 1, 0)
        for code in reversed(codes):
            _xtst.XTestFakeKeyEvent(self.dpy, code, 0, 0)
        _x.XFlush(self.dpy)
