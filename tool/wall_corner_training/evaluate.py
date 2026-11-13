"""Tries the wall-corner model on real photos, fed exactly as the app feeds it.

    python tool/wall_corner_training/evaluate.py CORNERS.onnx OUT_DIR PHOTO [PHOTO ...]

Uses the app's own depth and segmentation models (assets/models/, see
tool/fetch_wall_model.py and tool/fetch_wall_segmenter.py). A PHOTO with a
.json beside it holding "wall_corners_px" (and "photo_px") is scored; in a
kitchen those are the corners as a salesperson marks them, the bottom ones
where the floor meets the cabinets. Writes one picture per photo to OUT_DIR:
the photo with the model's wall in red (its hidden bottom corners as yellow
rings) and the marked one in white, beside what the corner model was shown.
"""
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import synth  # noqa: E402
from preview import tile  # noqa: E402

MODELS = Path(__file__).resolve().parents[2] / "assets" / "models"
MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)


class Pipeline:
    """Photo to corners, as in the app."""

    def __init__(self, corners_path: str, n: int = 128):
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 4
        load = lambda p: ort.InferenceSession(str(p), opts, providers=["CPUExecutionProvider"])
        self.depth = load(MODELS / "wall_depth.onnx")
        self.seg = load(MODELS / "wall_segment.onnx")
        self.corners = load(corners_path)
        self.n = n

    def room_input(self, photo: Image.Image) -> np.ndarray:
        """What the corner model is shown for a photo."""
        photo = photo.convert("RGB")
        w, h = photo.size
        s = 518 / min(w, h)
        dw, dh = int(round(w * s / 14)) * 14, int(round(h * s / 14)) * 14
        x = np.asarray(photo.resize((dw, dh), Image.BICUBIC), np.float32) / 255
        x = ((x - MEAN) / STD).transpose(2, 0, 1)[None].astype(np.float32)
        inv = self.depth.run(None, {self.depth.get_inputs()[0].name: x})[0][0]
        depth01 = synth.normalise(inv)
        depth01 = np.asarray(Image.fromarray(depth01).resize((self.n, self.n), Image.BOX))

        x = np.asarray(photo.resize((512, 512), Image.BILINEAR), np.float32) / 127.5 - 1
        logits = self.seg.run(None, {self.seg.get_inputs()[0].name: x.transpose(2, 0, 1)[None]})[0][0]
        ids = logits.argmax(0).astype(np.uint8)
        if ids.shape != (self.n, self.n):
            ids = np.asarray(Image.fromarray(ids).resize((self.n, self.n), Image.NEAREST))
        return synth.to_input(depth01, synth.ade_to_classes(ids), w / h)

    def __call__(self, photo: Image.Image):
        """(corners (4, 2) as fractions, expected error of each (4,), the
        input, the hidden bottom-right and bottom-left corners (2, 2) or None
        for a model from before they were added)."""
        x = self.room_input(photo)
        out = self.corners.run(None, {self.corners.get_inputs()[0].name: x[None]})[0][0]
        half = len(out) // 2
        expected = out[half:half + 8].reshape(4, 2).max(1)
        hidden = out[8:half].reshape(-1, 2) if half > 8 else None
        return out[:8].reshape(4, 2), expected, x, hidden


def main():
    corners_path, out_dir, photos = sys.argv[1], Path(sys.argv[2]), sys.argv[3:]
    out_dir.mkdir(parents=True, exist_ok=True)
    pipe = Pipeline(corners_path)
    for path in photos:
        photo = Image.open(path).convert("RGB")
        w, h = photo.size
        corners, expected, x, hidden = pipe(photo)
        truth_path = Path(path).with_suffix(".json")
        truth = None
        if truth_path.exists():
            t = json.loads(truth_path.read_text(encoding="utf-8"))
            tw, th = t.get("photo_px", [w, h])
            truth = np.array(t["wall_corners_px"], float) / [tw, th]
        line = f"{Path(path).stem:14s} expects to be off by {expected.max() * 100:4.1f}%"
        if truth is not None:
            err = np.hypot(*((corners - truth) * [w, h]).T) / w
            line += "  corners off by " + ", ".join(f"{e * 100:.1f}%" for e in err) + f" of the width (worst {err.max() * w:.0f} px)"
        print(line, flush=True)

        view = photo.copy()
        view.thumbnail((768, 768))
        d = ImageDraw.Draw(view)
        vw, vh = view.size
        if truth is not None:
            q = [(a * vw, b * vh) for a, b in truth]
            d.line(q + [q[0]], fill=(255, 255, 255), width=3)
        q = [(a * vw, b * vh) for a, b in corners]
        d.line(q + [q[0]], fill=(255, 30, 30), width=4)
        for a, b in hidden if hidden is not None else []:
            d.ellipse((a * vw - 6, b * vh - 6, a * vw + 6, b * vh + 6), outline=(255, 220, 0), width=3)
        points = corners if hidden is None else np.concatenate([corners, hidden])
        seen = tile(x, points.reshape(-1), size=vh // 2 * 2 // 2)
        sheet = Image.new("RGB", (vw + seen.width + 8, max(vh, seen.height)), "white")
        sheet.paste(view, (0, 0))
        sheet.paste(seen, (vw + 8, 0))
        sheet.save(out_dir / f"{Path(path).stem}.png")


if __name__ == "__main__":
    main()
