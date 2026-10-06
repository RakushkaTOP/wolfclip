import json, pathlib
for i in json.loads((pathlib.Path.home() / ".local/share/wolfclip/history.json").read_text()):
    print(i["kind"], "|", i.get("app_name"), "|", (i.get("text") or i.get("image_file") or "")[:50].replace("\n", " "))
