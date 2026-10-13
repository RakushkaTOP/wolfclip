<div align="center">

<img src="docs/icon.png" width="112" alt="WolfClip icon">

# WolfClip

**Clipboard history for macOS and Linux — the Win+V you were missing.**

Press one shortcut in any app, pick anything you copied earlier, and it lands right where you type.

[![Download](https://img.shields.io/github/v/release/RakushkaTOP/wolfclip?label=download&color=4F8CFF)](https://github.com/RakushkaTOP/wolfclip/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple)
![Linux](https://img.shields.io/badge/Linux-GTK%204-111?logo=linux&logoColor=white)
[![Apache 2.0 License](https://img.shields.io/badge/license-Apache%202.0-111)](LICENSE)

[Website](https://rakushkatop.github.io/wolfclip/) · English · [Русский](README.ru.md)

<br>

<img src="docs/demo.gif" width="620" alt="WolfClip: open, browse, search, filter and pin clipboard history">

</div>

<br>

## Why WolfClip

- **Instant paste.** Choose an item and WolfClip pastes it into the app you were in. No extra keystrokes.
- **Everything you copy.** Text, links, colors, code, images and files, each shown the way it reads best. A swatch for `#4F8CFF`, a thumbnail for a screenshot, a monospace block for code.
- **Find it in a second.** Start typing to search, `Tab` through filters, or press `⌘1`–`⌘9` to paste one of the first nine items.
- **Pins that stay.** Keep addresses, snippets and templates at the top. Pinned items never expire.
- **Keyboard first, mouse friendly.** Arrows, Enter, Escape, plus click, hover actions and a context menu.
- **Private by design.** Passwords copied from password managers are never recorded. History stays on your computer.
- **Native and light.** Swift and SwiftUI on macOS, GTK 4 on Linux. No Electron, near-zero CPU while idle.
- **Dark, light or system.** Speaks English and Russian, picked from your system language.

<br>

<p align="center">
  <img src="docs/themes.png" width="860" alt="Dark and light themes on macOS">
</p>

<br>

## Install

### macOS

With [Homebrew](https://brew.sh):

```bash
brew install --cask rakushkatop/tap/wolfclip
```

Then open WolfClip and allow **Accessibility** when it asks (step 3 below).

Or by hand:

1. Download **WolfClip-macOS.zip** from the [latest release](https://github.com/RakushkaTOP/wolfclip/releases/latest) and drag **WolfClip** into **Applications**.
2. Open it. The app is not notarized by Apple, so the first time macOS asks you to confirm. Open **System Settings → Privacy & Security** and click **Open Anyway**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/WolfClip.app
   ```
3. Allow **Accessibility** when WolfClip asks. It needs this to press `⌘V` for you and to open next to the text cursor. Without it, picks are only copied.

WolfClip lives in the menu bar and starts at login. Press **⇧⌘V** anywhere.

Updates install themselves. WolfClip checks GitHub Releases at launch and every 6 hours, verifies the download's SHA-256 and code signature, then swaps itself in place and restarts while the history window is closed. History, pinned items, settings and the Accessibility permission stay as they were. You can turn this off or check by hand in **Settings → Updates**. Version 1.0.0 has no updater, so install 1.0.1 by hand once.

<details>
<summary>Build from source</summary>

Only the Xcode Command Line Tools are needed:

```bash
git clone https://github.com/RakushkaTOP/wolfclip.git
cd wolfclip/macos
./build.sh install          # arm64; UNIVERSAL=1 ./build.sh install for Intel + Apple silicon
```

</details>

### Linux

```bash
curl -L https://github.com/RakushkaTOP/wolfclip/releases/latest/download/wolfclip-linux.tar.gz | tar xz
cd wolfclip-linux && ./install.sh
```

The installer checks for Python 3 with GTK 4. If they are missing, it offers to install them with `apt`, `dnf`, `pacman` or `zypper`. Everything else goes into your home folder. To remove WolfClip, run `./uninstall.sh` (add `--purge` to delete the history too).

Press **Super+V** in any app.

<p align="center">
  <img src="docs/linux.png" width="560" alt="WolfClip on Linux">
</p>

| Session | Shortcut | Auto-paste | Opens at |
|---|---|---|---|
| **X11** | Built in (Super+V, configurable) | Built in | Mouse pointer |
| **Wayland** (beta) | Bind `wolfclip --toggle` in system settings (Settings has a button for GNOME) | With [`wtype`](https://github.com/atx/wtype) or [`ydotool`](https://github.com/ReimuNotMoe/ydotool) | Placed by the compositor |

X11 is the tested setup. On Wayland, WolfClip runs through XWayland to follow the clipboard, and how well that works depends on the compositor. Reports are welcome.

<br>

## Shortcuts

| | macOS | Linux |
|---|---|---|
| Open history | `⇧⌘V` | `Super+V` |
| Move | `↑` `↓` | `↑` `↓` |
| Paste | `↵` or click | `Enter` or click |
| Paste as plain text | `⇧↵` | `Shift+Enter` |
| Paste item 1–9 | `⌘1`–`⌘9` | `Ctrl+1`–`Ctrl+9` |
| Copy without pasting | `⌘C` | `Ctrl+C` |
| Pin / unpin | `⌘P` | `Ctrl+P` |
| Delete | `⌘⌫` | `Ctrl+Delete` |
| Next / previous filter | `Tab` / `⇧Tab` | `Tab` / `Shift+Tab` |
| Clear search, close | `Esc` | `Esc` |

The shortcut can be changed in Settings. On macOS, `⇧⌘V` replaces "Paste and Match Style" in the apps that use it. Pick `⌥⌘V` or another option if you rely on it.

<br>

## Compared with other clipboard managers

| | Price | Source | Runs on |
|---|---|---|---|
| **WolfClip** | Free | Open source, Apache 2.0 | macOS 14+, Linux |
| [Maccy](https://github.com/p0deje/Maccy) | Free on GitHub, $9.99 in the Mac App Store | Open source, MIT | macOS |
| [CopyQ](https://github.com/hluk/CopyQ) | Free | Open source, GPL-3.0 | macOS, Linux, Windows |
| Spotlight clipboard | Built into macOS 26, off by default | Apple | macOS 26+ |
| [Raycast](https://www.raycast.com/pricing) | Clipboard history in the free plan (3 months), Pro $10/month | Closed source | macOS |
| [PastePal](https://apps.apple.com/us/app/clipboard-manager-pastepal/id1503446680) | Free, Pro $14.99 once | Closed source | macOS |
| [Paste](https://pasteapp.io/pricing) | $2.49/month or $29.99/year | Closed source | macOS |

Prices and licenses as listed by each project in October 2026. Maccy and CopyQ are great open-source picks too. WolfClip is for people who want the Windows-style flow: one shortcut, pick, and it is pasted.

<br>

## FAQ

**Is there a Win+V clipboard history on Mac?** Not the Windows kind. WolfClip adds one: press `⇧⌘V` in any app, pick an item and it is pasted where you were typing.

**Doesn't macOS Tahoe already have clipboard history?** Yes. Since macOS 26, Spotlight has a Clipboard section. It is off by default and keeps items for up to 30 days. WolfClip adds pins that never expire, image and file previews, filters, `⌘1`–`⌘9` and paste straight into the app you were in. It also works on macOS 14 and 15 and on Linux.

**Is it free?** Yes. Free and open source under Apache 2.0, with no subscription and no account.

**Does it record passwords?** No. Items that password managers mark as secret are skipped, and the history never leaves your computer.

**Why does macOS say it can't verify WolfClip?** It is ad-hoc signed, not notarized by Apple. Homebrew takes care of this. For a manual download, see step 2 of [Install](#macos).

<br>

## Privacy

- Items that password managers mark as secret are skipped: the `org.nspasteboard` concealed and transient markers on macOS, the KDE password-manager hint on Linux.
- History is a local file: `~/Library/Application Support/WolfClip` on macOS, `~/.local/share/wolfclip` on Linux. Nothing from it is sent anywhere. The only network request is the update check on macOS: a plain GET to the GitHub Releases API.
- You can pause recording at any time from the menu.

<br>

## How it works

<details>
<summary>For the curious</summary>

**macOS.** A menu-bar app in Swift and SwiftUI. It checks the pasteboard change counter a few times per second, which is effectively free. The global shortcut is a Carbon hot key, so it needs no permissions. The history is a non-activating panel: it takes the keyboard without stealing focus from your app, so the paste goes right back where you were. Paste is a synthetic `⌘V`. The window is placed at the text caret through the Accessibility API, with the mouse pointer as a fallback.

**Linux.** Python 3 with GTK 4, no extra Python packages. The clipboard comes from GTK's change notifications. The hot key, focus handling and auto-paste talk to X11 directly (`XGrabKey`, EWMH, XTest) through `ctypes`. Terminals get `Ctrl+Shift+V` automatically. A Docker harness in [`linux/test`](linux/test) runs the app headless on Xvfb for testing.

</details>

<br>

## License

[Apache 2.0](LICENSE) © RakushkaTOP. Use it, change it, ship it, even commercially. When you redistribute it, keep the copyright, the license and the [NOTICE](NOTICE) file that credits the author, and mark what you changed.
