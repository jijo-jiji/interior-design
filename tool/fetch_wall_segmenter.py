"""Fetches the wall segmentation model into assets/models/ (not kept in git).

    pip install tflite2onnx onnx
    python tool/fetch_wall_segmenter.py

MLCommons' DeepLabV3+ MobileNetV2 trained on ADE20K (Apache 2.0, from
github.com/mlcommons/mobile_models): labels every pixel as wall, floor,
ceiling, window, door, cabinet, curtain, ... The app uses it to find the
windows and doors on the wall. This converts the published TFLite file to
ONNX (the app's format), cut to the 32 class scores at 128 x 128.

Without it the app still builds and works; windows and doors are then
placed by hand. See assets/models/LICENSE-deeplab-ade20k.txt.
"""
import hashlib
import sys
import tempfile
import urllib.request
from pathlib import Path

URL = ("https://raw.githubusercontent.com/mlcommons/mobile_models/"
       "main/v0_7/tflite/deeplabv3_mnv2_ade20k_float.tflite")
# Git's blob id for the file (GitHub's own checksum of it).
GIT_SHA1 = "6ef580589ccd5c39dbcda73d01edda9ecbf2c972"
OUT = Path(__file__).resolve().parent.parent / "assets" / "models" / "wall_segment.onnx"


def git_sha1(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def convert(tflite_path: str, out_path: Path) -> None:
    import onnx
    import tflite
    import tflite2onnx
    from tflite2onnx.layout import Layout
    from tflite2onnx.op.common import Operator, OpFactory

    # tflite2onnx has no ARG_MAX (the model's last step); a stand-in lets the
    # graph parse, and the tail is cut off below anyway.
    class ArgMax(Operator):
        TypeMapping = {tflite.BuiltinOperator.ARG_MAX: "ArgMax"}

        def __init__(self, TFactory, index):
            super().__init__(TFactory, index)
            self.attrs["axis"] = 1
            self.attrs["keepdims"] = 0
            self.setInited()

        @property
        def type(self):
            return "ArgMax"

        def parse(self):
            self.parseInput(0, Layout("NHWC", "NCHW"))
            self.parseOutput(0)
            self.setParsed()

        def propagatableTensors(self):
            return list()

        def transform(self):
            pass

    if tflite.BuiltinOperator.ARG_MAX not in OpFactory.registry:
        OpFactory.register(ArgMax)

    # The model's resizes use TF1's default mode, which tflite2onnx refuses;
    # let it through as half-pixel, then set ONNX's matching mode below.
    tflite.ResizeBilinearOptions.HalfPixelCenters = lambda self: True

    with tempfile.TemporaryDirectory() as tmp:
        full = str(Path(tmp) / "full.onnx")
        tflite2onnx.convert(tflite_path, full)
        model = onnx.load(full)
        for node in model.graph.node:
            if node.op_type == "Resize":
                for attr in node.attribute:
                    if attr.name == "coordinate_transformation_mode":
                        attr.s = b"asymmetric"  # TF1's default
        onnx.save(model, full)
        resizes = [n for n in model.graph.node if n.op_type == "Resize"]
        logits = resizes[-1].input[0]  # the class scores, before upsampling
        onnx.utils.extract_model(full, str(out_path), [model.graph.input[0].name], [logits],
                                 check_model=False)
    onnx.checker.check_model(onnx.load(str(out_path)))


if __name__ == "__main__":
    if OUT.exists():
        print(f"Already there: {OUT}")
        sys.exit(0)
    try:
        import onnx  # noqa: F401
        import tflite2onnx  # noqa: F401
    except ImportError:
        sys.exit("Needs: pip install tflite2onnx onnx")
    print("Downloading 9 MB ...")
    data = urllib.request.urlopen(URL, timeout=120).read()
    if git_sha1(data) != GIT_SHA1:
        sys.exit("Checksum mismatch: the download was not used.")
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "deeplab.tflite"
        src.write_bytes(data)
        convert(str(src), OUT)
    print(f"Done: {OUT}")
