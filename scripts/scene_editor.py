#!/usr/bin/env python3
"""A drag-and-drop editor for Spin's scene placements.

Usage: python3 scripts/scene_editor.py   then open http://localhost:8765

Shows a scene's background photo with handles for the sleeve's four corners,
the record (centre, width, depth) and the occluder outline that hides the
sleeve's bottom behind the stand's lip. Save writes those fields into the
scene's scene.json in the repo and leaves every other field alone.
Only listens on 127.0.0.1.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENES = ROOT / "Plugins/SpinPlugin/Sources/SpinPlugin/Scene/Resources/scenes"
HTML = Path(__file__).with_name("scene_editor.html")
ARTWORK = Path.home() / "Library/Containers/org.ahlab.Perch/Data/Library/Application Support/Perch/Plugins/org.ahlab.perch.spin/Artwork"


def scene_ids():
    return sorted(p.name for p in SCENES.iterdir() if (p / "scene.json").exists())


class Handler(BaseHTTPRequestHandler):
    def send(self, code, body, kind="application/json"):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parts = self.path.split("?")[0].strip("/").split("/")
        if parts == [""]:
            return self.send(200, HTML.read_bytes(), "text/html; charset=utf-8")
        if parts == ["scenes"]:
            return self.send(200, json.dumps(scene_ids()))
        if len(parts) == 2 and parts[0] == "scene" and parts[1] in scene_ids():
            return self.send(200, (SCENES / parts[1] / "scene.json").read_bytes())
        if len(parts) == 2 and parts[0] == "bg" and parts[1] in scene_ids():
            return self.send(200, (SCENES / parts[1] / "background.jpg").read_bytes(), "image/jpeg")
        if parts == ["art"]:
            files = sorted(ARTWORK.glob("*"), key=os.path.getmtime, reverse=True) if ARTWORK.exists() else []
            if files:
                return self.send(200, files[0].read_bytes(), "image/jpeg")
            return self.send(404, "{}")
        self.send(404, "{}")

    def do_POST(self):
        parts = self.path.strip("/").split("/")
        if len(parts) != 2 or parts[0] != "save" or parts[1] not in scene_ids():
            return self.send(404, "{}")
        update = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        path = SCENES / parts[1] / "scene.json"
        scene = json.loads(path.read_text())
        scene["platter"] = update["platter"]
        scene["sleeve"]["corners"] = update["corners"]
        scene["occluders"] = update["occluders"]
        path.write_text(format_scene(scene))
        print(f"saved {path.relative_to(ROOT)}", flush=True)
        self.send(200, json.dumps({"saved": str(path.relative_to(ROOT))}))

    def log_message(self, *args):
        pass


def format_scene(scene):
    """One key per line, small objects and point lists kept on one line."""
    lines = []
    for key, value in scene.items():
        lines.append(f'  "{key}": {json.dumps(value, separators=(", ", ": "))}')
    return "{\n" + ",\n".join(lines) + "\n}\n"


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"Scene editor on http://localhost:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
