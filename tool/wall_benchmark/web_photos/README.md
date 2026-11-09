# Real photos from Wikimedia Commons

Two openly licensed photos of real rooms, each showing a whole front wall with
its ceiling and floor. Each `.json` holds the source, licence and author, plus
the wall's four corners as marked by hand from 4× zoomed crops (about ±3 px,
in order top-left, top-right, bottom-right, bottom-left). There are no tape
measurements, so these test where the corners land, not millimetres.

The photos themselves are not kept in the repo (CC BY-SA 4.0, by Yelderberry).
Fetch them at the size the corners were marked on:

```bash
python tool/wall_benchmark/fetch_commons.py photos 1280 "File:Apartment Room 2025-10-06 1.jpg" "File:Apartment Room 2025-10-12 2.jpg"
```

That writes `photos/01.jpg` and `photos/02.jpg`. Rename them to
`apartment-1.jpg` and `apartment-2.jpg` beside these `.json` files, then run
`depth_corners.py` on them.

Results (2026-11-09):

| Photo | Depth model's corners vs hand-marked | Points on the wall off by | App's lean check, true corners |
|---|---|---|---|
| apartment-1 | 3–11 px | median 24 mm, worst 55 mm | 0.02° (no warning) |
| apartment-2 | 2–8 px | median 16 mm, worst 39 mm | 0.78° (no warning) |

The millimetre column assumes a 2,700 mm ceiling.
