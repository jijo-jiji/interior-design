"""Fetches the wall-corner model into assets/models/ (not kept in git: 27 MB).

    python tool/fetch_wall_model.py

Without it the app still builds and works; it just doesn't suggest the wall's
corners on a photo. See assets/models/LICENSE-depth-anything-v2.txt.
"""
import hashlib
import sys
import urllib.request
from pathlib import Path

URL = ("https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/"
       "4472b7362082ad9968fee890ca0f1e5aca36b93d/onnx/model_quantized.onnx")
SHA256 = "fcf51f1b230362b28690bb9d1809bf0431f29cad20534e3f589bd7285547f20d"
OUT = Path(__file__).resolve().parent.parent / "assets" / "models" / "wall_depth.onnx"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


if OUT.exists() and sha256(OUT) == SHA256:
    print(f"Already there: {OUT}")
    sys.exit(0)
tmp = OUT.with_suffix(".part")
print(f"Downloading 27 MB to {OUT} ...")
urllib.request.urlretrieve(URL, tmp)
if sha256(tmp) != SHA256:
    tmp.unlink()
    sys.exit("Checksum mismatch: the download was not kept.")
tmp.replace(OUT)
print("Done, checksum OK.")
