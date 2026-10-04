#!/usr/bin/env python3
"""Generate an empty-room background for the Spin plugin with Gemini.

Usage: GEMINI_API_KEY=... scripts/generate_scene.py <out.jpg> "<prompt>" [model]

The photo must not contain a record, album art or text: the plugin draws
those. Only the prompt leaves this machine.
"""
import base64, json, os, sys, urllib.request

COMMON = (
    " Photorealistic interior photograph, 16:9, 35mm lens, camera standing in front of the "
    "desk and looking down at it at about 35 degrees, so the top of the turntable's platter "
    "reads as a clear wide ellipse. The turntable is large in frame, about a third of the "
    "image width, with NO dust cover or lid, and an EMPTY platter: no vinyl record on it. "
    "Nothing in the scene has any text, logo, label or artwork. No people, no screens."
)

def main():
    out, prompt = sys.argv[1], sys.argv[2]
    model = sys.argv[3] if len(sys.argv) > 3 else "gemini-3-pro-image"
    body = {
        "contents": [{"parts": [{"text": prompt + COMMON}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": "16:9", "imageSize": "4K"},
        },
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    req = urllib.request.Request(url, json.dumps(body).encode(), {
        "Content-Type": "application/json", "x-goog-api-key": os.environ["GEMINI_API_KEY"],
    })
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.load(resp)
    for part in data["candidates"][0]["content"]["parts"]:
        inline = part.get("inlineData") or part.get("inline_data")
        if inline:
            with open(out, "wb") as f:
                f.write(base64.b64decode(inline["data"]))
            print(out)
            return
    sys.exit("no image in response: " + json.dumps(data)[:500])

if __name__ == "__main__":
    main()
