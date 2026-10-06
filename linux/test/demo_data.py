"""Writes the English demo history used for README screenshots."""
import json, pathlib, shutil, time, uuid
data = pathlib.Path.home() / ".local/share/wolfclip"
(data / "images").mkdir(parents=True, exist_ok=True)
shutil.copy("/out/landscape.png", data / "images/landscape.png")
now = time.time()
def item(kind, text=None, app=None, ago=0, **extra):
    d = {"id": uuid.uuid4().hex, "kind": kind, "fingerprint": f"{kind}:{uuid.uuid4().hex}", "date": now - ago, "pinned": False,
         "app_name": app}
    if text is not None:
        d.update(text=text, chars=len(text), lines=text.count("\n") + 1)
    d.update(extra)
    return d
items = [
    item("text", "Moved the design review to Thursday, 3 PM — I'll send the link an hour before.", "Text Editor", 20),
    item("link", "https://github.com/RakushkaTOP/wolfclip", "Firefox", 140),
    item("image", None, "Image Viewer", 600, image_file="landscape.png", width=1280, height=720),
    item("text", "def paste(item):\n    clipboard.write(item)\n    keyboard.press('ctrl+v')", "Code", 1500),
    item("color", "#4F8CFF", "Firefox", 2400),
    item("files", "/home/user/Documents/brand-guidelines.pdf", "Files", 5400, files=["file:///home/user/Documents/brand-guidelines.pdf"]),
    item("text", "sudo apt install python3-gi gir1.2-gtk-4.0", "Terminal", 9000),
]
(data / "history.json").write_text(json.dumps(items))
print("demo:", len(items))
