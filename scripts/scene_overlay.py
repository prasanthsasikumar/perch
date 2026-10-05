#!/usr/bin/env python3
"""Draw a scene.json's record, tonearm and sleeve over its background.

Usage: scripts/scene_overlay.py <scene folder> <out.png>
Mirrors SceneLayout's conventions: fractions of the image, origin top-left,
lengths as fractions of width, tonearm 0° = straight down, positive = tip left.
"""
import json, math, sys
from PIL import Image, ImageDraw

folder, out = sys.argv[1], sys.argv[2]
scene = json.load(open(f"{folder}/scene.json"))
img = Image.open(f"{folder}/background.jpg").convert("RGB")
w, h = img.size
d = ImageDraw.Draw(img)
p = scene["platter"]
cx, cy, r = p["x"] * w, p["y"] * h, p["radius"] * w
ry = r * p["squash"]
d.ellipse([cx - r, cy - ry, cx + r, cy + ry], outline=(255, 0, 0), width=4)
d.ellipse([cx - r * .36, cy - ry * .36, cx + r * .36, cy + ry * .36], outline=(255, 255, 0), width=3)
arm = scene.get("tonearm")
if arm:
    px, py, length = arm["pivotX"] * w, arm["pivotY"] * h, arm["length"] * w
    for angle, colour in ((arm["restAngle"], (0, 128, 255)), (arm["playAngle"], (0, 255, 0))):
        t = math.radians(angle)
        d.line([px, py, px - length * math.sin(t), py + length * math.cos(t)], fill=colour, width=5)
s = scene["sleeve"]
sx, sy, half = s["x"] * w, s["y"] * h, s["size"] * w / 2
d.rectangle([sx - half, sy - half, sx + half, sy + half], outline=(255, 0, 255), width=4)
img.save(out)
print(out)
