# Linux test harness

Runs WolfClip headless on Xvfb + openbox + xcompmgr inside Docker, drives it with `xdotool`,
and checks clipboard capture, the global shortcut and auto-paste into a real GTK text field.

```bash
docker build -t wolfclip-test linux/test
docker run -d --name wc -v "$PWD":/src -v "$PWD/linux/test/out":/out wolfclip-test sleep infinity
docker exec wc /src/linux/test/session.sh                         # X server, WM, compositor
docker exec -d wc /src/linux/test/x python3 /src/linux/test/target.py  # paste target "Notes"
docker exec -d -w /src/linux wc /src/linux/test/x python3 -m wolfclip
docker exec wc /src/linux/test/x /src/linux/test/copy_samples.sh    # copy text, link, color, code, image, file
docker exec wc /src/linux/test/x xdotool key super+v Return          # open history, paste the first item
cat linux/test/out/target.txt
```

- `x` — runs a command inside the session (DISPLAY + shared D-Bus).
- `dump.py` — prints the recorded history.
- `grab_other.py` — holds Super+V like another app would (shortcut conflict test).
- `demo_data.py`, `matte.sh` — README screenshots: sample history and a transparent capture of the window.
