# Wall benchmark

How accurate is the camera route on real walls? Measure some walls with a
tape, run them through the app, and compare.

## 1. Measure (per wall)

With a tape, in millimetres:

- the wall's **width** (corner to corner, at about waist height) and **height**
  (floor to ceiling);
- for every window and door: its **width** and **height**, its **distance from
  the wall's left corner** to its left edge, and its **distance from the floor**
  to its bottom edge (0 for a door).

Write them in a copy of [`truth-template.csv`](truth-template.csv), one row per
window or door. A wall with no openings gets one row with the opening columns
left empty.

## 2. Photograph and run through the app

For each wall, take three photos with the app's camera screen: head-on, from
about 15° to one side, and from about 30° to the other side. All four corners
of the wall must be in frame.

For each photo:

1. Type the tape's width and height on the wall-size screen.
2. Mark the corners, then the windows and doors, as a salesperson would.
3. Send a quote. Put the quote number in the truth file's `quote_id` column.

## 3. Compare

From the repository root:

```bash
python tool/wall_benchmark/evaluate.py backend/projects_db.json my-walls.csv
```

It prints, for every opening, how far the app's position and size are from the
tape, and a summary (median and worst error, per view). It also shows each
photo's lens source and tilt, so poor results can be traced to their cause.

## Synthetic photos

`make_synthetic.py` renders rooms photographed from known angles, with the
answers: the wall's and openings' corners in pixels, and their sizes in mm.
They test the app end to end without a tape, and seed the photo set a learned
corner finder will be trained on.

```bash
python tool/wall_benchmark/make_synthetic.py out/
```

## Finding the corners automatically (prototype)

`depth_corners.py` finds the front wall's corners from a single photo using
Depth Anything V2 Small, a depth model (Apache 2.0). The front wall is the large
flat surface in the middle of the photo, and each of its sides is fitted as a
straight line. The usage and model download are at the top of the file.

Results so far, on the synthetic photos:

| Photo | Corners off by | Openings off by |
|---|---|---|
| From the left, 25° | about 6–46 px | window 135–149 mm, door 207–238 mm |
| From the right, 20° and higher | about 4–40 px | window 91 mm, door 62 mm |
| Head-on (flat, untextured render) | fails | |

The numbers vary a little between runs, because the fitting samples at random.

On **real photos** it does much better: on two rooms from Wikimedia Commons
(see [`web_photos/`](web_photos/README.md)), the corners land 2–11 px from
hand-marked ones. That puts points on the wall 16–24 mm off typically, and
39–55 mm at worst. The renders were harder for it because they have no texture.

Still to do: run it on the tape-measured benchmark walls, and on kitchens with
cabinets already against the wall.
