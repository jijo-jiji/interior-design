"""Fetches Wikimedia Commons photos at a given width, with their licence.

    python fetch_commons.py OUT_DIR WIDTH "File:A.jpg" "File:B.jpg" ...

Writes OUT_DIR/<n>.jpg and OUT_DIR/sources.json (title, licence, author, page).
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
UA = "interior-design-wall-test/0.1 (internal accuracy testing; Python urllib)"


def get(url, tries=6):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == tries - 1:
                raise
            wait = int(e.headers.get("Retry-After") or 0) or 10 * (attempt + 1)
            print(f"  rate-limited, waiting {wait}s", flush=True)
            time.sleep(wait)


out, width, titles = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
out.mkdir(parents=True, exist_ok=True)
api = ("https://commons.wikimedia.org/w/api.php?action=query&prop=imageinfo"
       "&iiprop=url|size|extmetadata&format=json&iiurlwidth=%d&titles=%s")
sources = []
for n, title in enumerate(titles, 1):
    data = json.loads(get(api % (width, urllib.parse.quote(title))))
    page = next(iter(data["query"]["pages"].values()))
    ii = page["imageinfo"][0]
    md = ii.get("extmetadata", {})
    strip = lambda s: re.sub(r"<[^>]+>", "", s or "").strip()
    img = get(ii.get("thumburl") or ii["url"])
    name = f"{n:02d}.jpg"
    (out / name).write_bytes(img)
    sources.append({
        "file": name,
        "title": title,
        "licence": strip(md.get("LicenseShortName", {}).get("value")),
        "author": strip(md.get("Artist", {}).get("value"))[:120],
        "page": ii.get("descriptionurl"),
        "bytes": len(img),
    })
    print(f"{name} {len(img) / 1e3:6.0f} KB  {sources[-1]['licence']:14s} {title[5:70]}")
    time.sleep(3)
(out / "sources.json").write_text(json.dumps(sources, indent=2, ensure_ascii=False), encoding="utf-8")
