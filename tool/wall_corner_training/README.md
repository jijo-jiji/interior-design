# Training the wall-corner model

The app finds the corners of the wall in front of the camera in two ways:

1. **Flat patches in the depth map** (`lib/features/trace/utils/corner_finder.dart`).
   This works in rooms whose walls show. It turns kitchens down, because
   cabinets hide the walls' edges.
2. **This model** (`assets/models/wall_corners.onnx`), tried when the first
   way finds nothing.

## What the model sees and outputs

- **It doesn't see the photo.** It reads what the app's two other models make
  of it:
  - the depth map (Depth Anything V2 Small);
  - the labels (DeepLabV3+): wall, floor, ceiling, window, cabinet, door,
    other.

  Both are shrunk to 128 × 128.
- **Why:** it can be trained on made-up kitchens rendered in code, where the
  hidden corners are known exactly. No photos have to be collected or marked
  first.
- **Output:** six points, plus how far off it expects each to be.
  - **The four corners as a salesperson marks them.** In a kitchen the bottom
    ones go where the floor visibly meets the base cabinets, not on the
    hidden line behind them. With cabinets along the front wall and a side
    wall, that is the inside corner of the L at floor level.
  - **The two hidden bottom corners,** where the wall really meets the floor
    behind the cabinets. The app shows and lets you drag only the four
    corners. It measures the wall (straightening, size estimate, lean check,
    windows and doors) from the hidden points, which keep their distance
    from the bottom corners when those are dragged. If no cabinets stand
    there, the two sets are the same.
- **When the app uses it:**
  - The corners are used only when every expected error is 3% of the photo
    or less (`kLearnedMaxError` in `lib/features/trace/utils/learned_corners.dart`).
    Otherwise the salesperson places them by hand, as before.
  - The hidden points are used when the model expects them within 5%
    (`kHiddenMaxError`).
- **Why the corners follow the floor line:** that is how the user marks them,
  and what can be checked by eye. Run 2 and earlier put the bottom corners
  on the hidden line, so they floated on the cabinet doors.

## Files

| File | What it does |
|---|---|
| `synth.py` | Made-up rooms and kitchens: base, wall and tall cabinets, hoods, soffits, islands, windows, doors, clutter. Ray-cast to depth + labels, then roughened to look like the real models' output. |
| `preview.py` | A sheet of samples, to check the generator by eye. |
| `model.py` | The network: a small CNN, 1.8 M weights, 7 MB. |
| `train.py` | Training, on the CPU. Exports `wall_corners.onnx` for the app. |
| `evaluate.py` | Runs the model on real photos, fed exactly as the app feeds it. Scores the photos that have hand-marked corners. |

## Running it

Needs Python with `torch` (the CPU build is enough), `numpy`, `pillow`,
`onnx` and `onnxruntime`. Evaluation also needs `assets/models/wall_depth.onnx`
and `wall_segment.onnx` (`tool/fetch_wall_model.py`,
`tool/fetch_wall_segmenter.py`).

```bash
R=tool/wall_corner_training
python $R/preview.py preview.png
python $R/train.py $R/runs/run1 --steps 10000
python $R/evaluate.py $R/runs/run1/wall_corners.onnx $R/runs/eval1 photo1.jpg photo2.jpg
cp $R/runs/run1/wall_corners.onnx assets/models/wall_corners.onnx
```

- **Where runs are kept:** `runs/` holds each run's checkpoint (`corner.pt`,
  22 MB), log and exported model, plus the evaluation pictures. It is kept
  out of git; the shipped model is `assets/models/wall_corners.onnx`, which
  is in git.
  - `runs/run1`: 10,000 steps on the processor.
  - `runs/run2`: run 1 continued to 30,000 steps.
  - `runs/run3`: from run 2, with the bottom corners on the visible floor
    line; the shipped model.
  - `runs/photos`: the real photos used for evaluation.
  - `runs/eval1`, `runs/eval2`: what each run made of them.
- **Graphics card:** `train.py` uses it whenever PyTorch was installed with
  CUDA. On this laptop's RTX 3060 (driver supports CUDA 13.3) that is
  `pip install "torch==2.15.0+cu132" --index-url https://download.pytorch.org/whl/cu132`,
  a 2.1 GB download.
  - **Where to put the environment:** in a folder with a short path, such as
    `tool/wall_corner_training/.venv` (gitignored). The package has very long
    file paths and won't install deeper, for example in the temp folder.
  - **Workers:** the samples are still made on the processor, so give it
    `--workers 12`.
- **Speed on this laptop:**

  | Setup | Time a step |
  |---|---|
  | Processor only | 0.78–0.93 s |
  | Graphics card, old sample maker | 0.57 s |
  | Graphics card, faster render and mirrored samples | 0.10 s |

  - **At 0.10 s:** 10,000 steps take about 17 minutes. The card stays near
    73 °C at about 55 W, and the processor stays busy making samples.
  - **Faster render:** each box is tested only against the pixels inside its
    outline on the photo.
  - **Mirrored samples:** each sample is also used flipped left to right.
- **Resuming:** `--resume` continues from `corner.pt` in the output folder.
- **Changing the input:** `lib/features/trace/utils/learned_corners.dart`
  builds the same input in Dart. If `synth.normalise`, the resize or the
  channels change, change it there too. `test/learned_corners_test.dart`
  checks the two give the same numbers.

## Results (2026-11-11)

### Run 3 (shipped): bottom corners on the visible floor line

- **Why:** the user checked run 2 on kitchen 09 and marked where the corners
  really go (`runs/photos/kitchen-09.json`). Two things were wrong:
  - **Bottom corners on the hidden line:** run 2 put them where the wall
    meets the floor behind the cabinets, so they floated on the cabinet
    doors.
  - **Top-left about 50 px off:** probably because the model sees only a
    128 × 128 version of the photo (not tested).
- **How it was trained:** started from run 2's weights, with the new answer
  (the four corners as marked, plus the two hidden bottom corners for
  measuring). 20,000 steps on the graphics card, 30 minutes.
- **Made-up validation set:** corners as marked 2.0% median; hidden bottom
  corners 1.8%.
- **Kitchen 09 against the user's marks,** in px for top-left, top-right,
  bottom-right and bottom-left:

  | Run | Off by | Decision |
  |---|---|---|
  | Run 2 | 52, 11, 71, 26 | Placed |
  | Run 3 | 50, 41, 44, 78 | Turned down; it expects to be 3.8% off |

  Run 3's whole outline sits about 40 px right of the marks.
- **Kitchens 03 and 08:** placed on the PC (2.5% and 2.9% expected), and
  they follow the user's convention by eye: bottom corners at the inside
  corners of the U at floor level, top corners at the ceiling corners.
- **On the tablet emulator:**
  - **Kitchen 03:** placed automatically. Measured from the hidden corners,
    its straightened wall stands upright with no lean warning:
    2,880 × 2,700 mm.
  - **Kitchen 08:** turned down there, though the PC says 2.9%, just under
    the 3% limit. The tablet prepares the photo (decoding, resizing) a little
    differently from the PC, which probably tipped it over. Not checked: the
    next step is to run the same photo through both and compare what the
    corner model is given.
  - **Kitchens 09 and 02:** turned down.
- **Cost:** fewer kitchens are placed automatically than with run 2, because
  run 2 placed bottom corners the user doesn't accept.
- **Snapping corners to straight lines in the photo** (a prototype, not
  shipped):
  - In the empty room it halved the error.
  - In kitchens it jumped to cabinet edges, which contrast more than the
    corner where two walls meet: 09 went from 52 to 107 px off.

### Runs 1 and 2: bottom corners on the hidden line

**Run 2** is run 1 continued from 10,000 to 30,000 steps; the last 18,000
were on the graphics card.

**Made-up validation set (1,024 rooms and kitchens):** distance from the
true corner, as a share of the photo's width.

| | Run 1 (10,000 steps) | Run 2 (30,000 steps, shipped) |
|---|---|---|
| Median corner | 2.21% | 1.79% |
| Worst 10% of corners | 11.0% | 9.8% |
| Kitchens, median | 2.37% | 1.91% |

**Real photos:** 2 empty rooms and 9 kitchens from Wikimedia Commons, kept
in `runs/photos/` with their sources. Each cell gives the expected error
(how far off the model expects to be), then the result.

| Photo | Run 1 | Run 2 |
|---|---|---|
| Empty room 1 | 0.6%; worst corner 30 px off the hand marks | 0.5%; worst corner 19 px off the hand marks |
| Kitchen 08 | 1.3%; right, by eye | 1.4%; right, by eye, right edge a little closer |
| Kitchen 09 | 1.3%; right, by eye | 1.6%; right, by eye, left edge a little closer |
| Kitchen 03 | 2.5%; side edges 40 px and 21 px off the backsplash corners | 1.4%; 33 px and 38 px off |
| Kitchen 02 | 3.8%; wrong (cut off the fridge end of the wall), turned down | 4.0%; turned down |
| Kitchen 04 | 4.1%; wrong (left edge too far left), turned down | 3.7%; turned down |
| Kitchen 01 | 5.8%; turned down | 3.9%; turned down |
| Empty room 2 | 5.6%; wrong (took a glass door as part of the wall), turned down | 7.2%; turned down |
| Kitchens 05, 06, 07 | 8.7–10.8%; turned down | 9.4–10.9%; turned down |

- **What the 3% rule gives:** the same answers from both runs. On this set it
  keeps exactly the right ones.
  - Three of nine kitchens now get their corners automatically; before, none
    did.
  - The depth patches already get empty room 2 right.
- **Why run 2:** it is better on the made-up set and on empty room 1, and
  about the same on the kitchens. It also leaves a wider gap between the
  photos it is sure of (at most 1.6%) and those it got wrong (3.7% or more).
- **Tablet emulator (run 1):** kitchen 09 got its corners and size
  automatically, and its window was then found too.
- **Bottom edge in kitchens:** it sits a little above the cabinets' plinths.
  That is correct: the wall meets the floor behind the cabinets, which
  appears higher in the photo.
- **Accuracy on accepted kitchens:** corners are a few per cent off, so the
  lean check often still asks for a nudge.

## Next

- **Real kitchen photos to test on:** the 9 used above are from Wikimedia
  Commons. More of them, with corners marked by hand, would make the 3% rule
  safer to trust; `evaluate.py` scores any photo that has a `.json` beside it
  (`wall_corners_px`, `photo_px`).
- **Measure it in the field.** Each quote now records `suggested_by`
  (`planes` or `learned`) with `suggested_corners`, next to the corners the
  salesperson confirmed.
- **Train on real photos.** Once there are a few hundred confirmed kitchen
  photos, add them to training next to the made-up ones (they need their
  depth and labels worked out the same way).
- **Make it better at:**
  - fridges and tall units standing at the end of the wall (kitchen 02);
  - L-shaped runs coming towards the camera (kitchen 04).
