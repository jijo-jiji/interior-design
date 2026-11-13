# Camera feature ("Photo of the wall"): accuracy plan

## Progress (2026-11-08)

Your answers: photos often show the side walls and ceiling, the wall in front
is what matters, measurements are off, and an on-device ML model is fine.

**Done:**

- **Phase 2 first, because it fixes both problems.** The four lines are
  replaced by the front wall's four corners. Step 2 straightens that wall into a
  true rectangle of the typed size, which also crops away the side walls and
  ceiling. Windows and doors are marked on the straightened wall.
  - In simulation, a window comes back within 0.5 mm at 30°, where the old lines
    were more than 100 mm off. Taps 4 px off cost about 7 mm.
  - A magnifier shows under the finger while a corner is dragged.
- **Phase 1:**
  - The camera captures at 1080p instead of 720p.
  - A live level bubble shows on the capture screen.
  - The size check compares the corners' shape with the typed size, using the
    photo's lens from EXIF when it has one.
  - EXIF rotation was checked: Flutter's decoder already applies it, so photos
    need no re-saving.
  - Lines can no longer sit on the black bars, because corners are clamped to
    the photo.
- **Phase 0:** `tool/wall_benchmark/` holds the tape-measure instructions, a
  truth template, and an evaluator over saved quotes. It also has a renderer for
  synthetic angled photos with known answers.
- **Measurement record:** each quote now keeps how its wall was measured
  (`capture`: corners, photo size, lens, tilt), on the phone and on the office
  server.
- **Found on the emulator:** a corner dragged 100 px off barely changes the
  wall's proportions (0.6%) or the right angle (0.4°), yet moves the window
  224 mm and the door 495 mm. Four points always fit some rectangle in
  perspective, so no check on the corners alone can catch it.
  - The size check now only warns (misread tape, corner on the wrong wall) and
    never shows a tick.
- **Lean check (no ML):** on the straightened wall, every upright line in the
  room stands vertical when the corners are right: window and door frames,
  cabinet sides, even furniture in front of the wall. If they lean more than
  1.5°, step 2 says a corner is off.
  - On the test photos: right corners lean under 1°, taps a few pixels off
    stay under 1°, and the 100 px error leans 2.3–7.5°.
  - It needs upright edges to judge by. A blank wall gives no verdict.

**Needs your decision (Phases 3–4, machine learning):** see the end of this
file.

## Where the flow stood before

Camera → type the wall's width and height → drag four lines onto the photo's
wall edges → place windows and doors by hand → 3D.

## What the code does today, and why it drifts

1. **The scale assumes a flat, head-on photo.** The four lines form an
   axis-aligned rectangle (`lib/features/trace/providers/wall_provider.dart`,
   `scaleRatioX` / `scaleRatioY`). A photo taken at an angle shows the wall as
   a trapezoid, so mm-per-pixel changes across the wall. Nothing corrects it.
2. **Lines can sit on the black bars.** The photo is drawn with
   `BoxFit.contain` (`lib/shared/platform/photo_image_io.dart:9`,
   `trace_screen.dart:119`), but `moveEdge` clamps to the whole canvas
   (`wall_provider.dart:151-167`) and taps map to the canvas
   (`trace_screen.dart:55-61`). Whenever the photo's shape differs from the
   phone's, some of the canvas is black, and a line dragged there makes the
   wall look bigger than it is. Example: a 4:3 landscape photo in a portrait
   canvas leaves about 58% of the canvas black.
3. **The saved photo is never normalised.** Captured at
   `ResolutionPreset.high` with no orientation handling
   (`lib/features/trace/screens/camera_screen.dart:61-66`, `95-100`). Nothing
   checks that the saved file's rotation matches the preview, or that the guide
   box matches the saved frame. Needs checking on a real phone.
4. **The "level" overlay measures nothing.** `_GridOverlayPainter`
   (`camera_screen.dart:357-366`) only draws a crosshair. There is no
   accelerometer (no sensors package in `pubspec.yaml`), so a tilted phone is
   never caught. Tilt is the main cause of point 1.
5. **Wall size is typed, never checked against the photo.** The 3D wall uses the
   typed width and height (`payload_builder.dart`). A wrong tape reading, or
   lines in the wrong place, goes unnoticed.
6. **Every wall starts from arbitrary lines.** The lines start at 8% and 92%
   (`wall_provider.dart:37-40`), so each wall needs four manual drags before
   anything is right.
7. **No test uses a real photo.** The tests check the arithmetic
   (`scale_math_test.dart`, `payload_builder_test.dart`), not whether a photo of
   a known wall produces the right numbers.

## Plan

### Phase 0: measure before changing (small)

- Build a benchmark of 6 to 10 real walls. Tape-measure each wall's width and
  height, plus each window's position and size.
- Photograph each wall head-on, at about 15° tilt and at about 30° tilt, from
  two distances.
- Add a debug readout that shows what the app computes next to the tape
  values, and the error.
- On a phone, check: is the saved photo rotated compared with the preview, does
  the guide box match the saved frame, and how much black bar appears.
- Output: an error table. The targets for later phases come from these numbers,
  not from guesses.

### Phase 1: stop the obvious errors (small)

- Normalise the photo once, at capture: apply the EXIF rotation, match the saved
  frame to what the preview showed, save it upright. Everything downstream then
  sees one orientation.
- Clamp lines and taps to the photo's visible rectangle, not the canvas. Work out
  that rectangle from the image's real pixel size, using the same maths as
  `BoxFit.contain`.
- Add a tilt check with the accelerometer (`sensors_plus`). Show a live level
  bubble on the capture screen and warn when roll or pitch exceeds about 3°
  (proposed).
- In the wall step, compare the photo's lines with the typed size. If they
  imply a width or height more than about 5% away from the tape, say so before
  moving on (proposed threshold).

### Phase 2: correct the perspective (medium)

- Replace the four lines with the wall's four corner points.
- Solve a homography from the photo to a rectangle of the typed width × height.
  Four corners of a planar rectangle determine that mapping exactly, so no
  camera calibration is needed.
- Map every window and door through the inverse homography, so position and
  size come out in wall-plane millimetres.
- Keep the four-line mode for head-on shots. It is the same homography with
  axis-aligned corners, so the simple path stays simple.
- Tests: render synthetic photos (a rectangle with a window, under a known
  perspective transform, as the floor-plan test plans were made) and check that
  the recovered millimetres fall within the Phase 0 targets.

### Phase 3: find the wall and openings automatically (medium to large)

- Classical detection first: the wall quadrilateral from the strongest straight
  edges, bright rectangles for windows, and dark tall rectangles for doors, all
  in the rectified view.
- The salesperson confirms or drags what was found, instead of placing from
  scratch.
- Run it in a background isolate, as the floor-plan geometry does.
- Accept detections only when the benchmark passes. Otherwise fall back to
  manual corners and say so. Never silently guess.

### Phase 4: learned detection, only if Phase 3 misses the targets (large)

- A small on-device segmentation model (walls, openings, floor, ceiling),
  trained on labelled wall photos. This needs a few hundred labelled photos.
- The current Gonka gateway accepts text only, so any image model has to run on
  the device.
- Not started until the Phase 3 numbers are in.

### Phase 5: guidance and checks (small)

- Before capture: "whole wall in frame, phone upright, 1.5 to 2.5 m away", with
  the level bubble.
- After the boxes are placed: a side-by-side check of the photo with the boxes
  on it, and the 3D view. Prompt a retake if the wall is cut off.

## Order

Phase 0 and Phase 1 first. They are cheap and remove errors that are plainly
wrong. Phase 2 fixes accuracy at an angle. Phase 3 removes most of the dragging.
Phase 4 only if needed.

The payload keeps its shape (mm from the wall corner). An optional `capture`
block (tilt, corner points, rectification) is added, so designs made before this
change still open.

## Risks

- On-device speed on low-end phones. The emulator has 2 GB of RAM, so test
  Phase 3 on a real device.
- The browser camera path (`photo_flip`, the web build) must keep working.
  Phase 2 is tested on web too.
- Bright daylight: windows can look like the bright rectangles the detector
  searches for. The benchmark should include a daylight set.

## Open questions

1. What exactly is "off"? Windows in the wrong place, the wall looking wrong in
   3D, or the photo itself (rotated, cut off)? One example decides whether
   Phase 1 or Phase 2 comes first.
2. Can you collect the Phase 0 benchmark walls, with tape measurements?
3. Is a small on-device ML model (Phase 4) acceptable later, or should this stay
   geometry only?

## Floor plan (parked)

ML tuning for the plan reader needs ground truth: about 20 to 30 real plans,
each with its printed sizes and the true room sizes. Without them, the
thresholds can't be tuned. Not started.

## Machine learning: options and what each needs

The goal: the app places the four corners, the windows and the doors itself,
and the salesperson only confirms.

1. **Collect our own labelled photos (recommended first).** Every quote already
   records the corners the salesperson confirmed. Keeping the wall photo with
   it on the office server (as floor-plan pictures are kept) turns every quote
   into a training example. This needs your OK: photos of clients' homes would
   be stored on the office server.
2. **Prototype with an existing room-layout model, on the PC only.**
   `leVirve/lsun-room` (MIT code) labels front wall, side walls, ceiling and
   floor, which is the "wall in front" problem. Its weights were trained on
   LSUN Room Layout, whose commercial terms are unclear, so use it to measure
   what is possible, not to ship. Needs a download from Google Drive.
3. **Windows and doors.** MediaTek's DeepLabV3+ for MLPerf Mobile (Zenodo
   3966763, Apache 2.0, 45 MB archive, quantised for phones) segments ADE20K
   scenes. Check that its class list has wall, window and door before relying
   on it. ADE20K's own image terms also need checking for commercial use.
4. **Ship a small model trained on our photos** (from option 1), converted to
   TFLite and run on the phone, scored against the benchmark before it replaces
   manual corners.

## Progress (later on 2026-11-08): your go-ahead on the recommendations

**Photo collection: done, tested end to end on the emulator.**

- The quote sheet has a "Keep the wall photo" switch, on by default. It shows
  only for rooms measured from a wall photo.
- If kept, the photo goes to the office server with the quote, and only with
  the corners marked on it.
- The server saves it upright, re-encoded without metadata, so no GPS position
  or camera details survive, in `backend/wall_photos/` (ignored by git).
- No route serves it back out, and it never enters the database.
- Switching it off and sending again deletes the stored copy.
- The quote PDF tells the client: "A photo of your wall was kept on our office
  server to help us measure more accurately. It is never shared, and we delete
  it whenever you ask."
- The camera prompt now also says "Keep people out of the shot."

**The `lsun-room` test can't go ahead as planned.** Its weights on Google Drive
now ask for a Google sign-in. The other room-layout project
(`shuuchen/lsun-room-dsc`) needs permission from its author, and its GitHub
repo has no licence set.

**Alternative: Depth Anything V2 Small** (Apache 2.0; the larger versions are
non-commercial). It estimates how far away each pixel is. The front wall is
then the large flat surface facing the camera, and its corners are where it
meets the side walls, ceiling and floor.

- The phone-ready ONNX build `onnx-community/depth-anything-v2-small` is
  99.1 MB at full precision, or 27.3 MB in 8-bit, small enough for the app.
- The PC test also needs `onnxruntime` 1.31.1 (14.9 MB).
- Both are downloads that need your OK.

**Depth Anything test, on synthetic photos (PC):**

- The model is downloaded with its hash checked, and runs on the PC.
- `tool/wall_benchmark/depth_corners.py` finds the front wall as the flat
  surface in the middle of the photo, then fits a straight line to each side.
- On the two angled photos the corners come out about 4–46 px off, and the
  window and door 60–240 mm off. That's close enough to give the salesperson a
  starting point, not close enough to skip checking the corners.
- On a head-on photo of a plain, untextured wall it fails. The model reads the
  flat window as a hole into the distance, and the plain wall breaks into
  patches.
- Speed: about 1.6 s for depth plus 0.7 s for corners on the PC.

**Next:** real photos. When the benchmark walls are photographed, run
`depth_corners.py` on them:

- If corners mostly land within about 20 px, put the 27 MB model in the app as
  "suggested corners".
- If not, train a corner model on the collected photos.

**Depth model on real photos (2026-11-09), from Wikimedia Commons:**

- Two openly licensed apartment photos showing a whole front wall. I marked the
  true corners by hand from zoomed crops.
- The model's corners landed 2–11 px from them. With a 2,700 mm ceiling, that
  puts points on the wall 16–24 mm off typically, 39–55 mm at worst.
- That clears the "within about 20 px" bar set above. It's only two photos,
  both plain empty rooms; kitchens with cabinets are still untested.
- The app's lean check on these real photos:
  - right corners give 0.02° and 0.78°, so no false alarm;
  - a corner 80 px off always warns;
  - 40 px off warns half the time;
  - 20 px off almost never.
- Most web photos turned out unusable: real-estate shots usually crop off the
  ceiling or one end of the wall. 2 of 21 previews showed a whole front wall.
  The camera prompt ("all four corners showing") matters.

**Suggested corners in the app (2026-11-09):**

- **When the search runs:** as soon as a photo is chosen, the app looks for the
  front wall's corners on the phone, while the salesperson types the wall size.
- **What it uses:** Depth Anything V2 Small, 8-bit, 27 MB, run with
  `flutter_onnxruntime` 1.9.0. The corner finder is the Python prototype ported
  to Dart (`lib/features/trace/utils/corner_finder.dart`).
- **Placing the dots:** if the salesperson hasn't touched the corners yet, the
  dots move onto the wall and the panel says to check them with the magnifier.
  If they have, the panel offers "Use them". If nothing is found, it says to
  place them by hand.
- **When there's no model:** in the browser, or in a build without the model
  file, nothing changes.
- **What the quote keeps:** the suggested corners, beside the confirmed ones
  (`capture.suggested_corners`), so every quote measures the model.
- **8-bit vs full model:** on the PC the 8-bit model was as accurate as the
  full one. Smaller inputs were faster but much less accurate, so it runs at
  518 px on the short side.
- **On the emulator, real photos:** the dots landed 8–11 px from the
  hand-marked corners. The search took about 4–5 s from choosing the photo, the
  first time including loading the model. Speed on a real tablet is untested.
- **App size:** about 83 MB for the 64-bit ARM build (was 90 MB universal). The
  universal APK is about 190 MB.

**Kitchens and the tablet (2026-11-09):**

- **Kitchens:** 9 real kitchen photos from Wikimedia Commons. The finder gave
  wrong corners on all 9, outlining a fridge, a backsplash strip or a run of
  wall cabinets as the wall, because in a kitchen the middle of the photo
  isn't the wall.
  - Fix: a room check. The answer must have a ceiling above, floor below
    (reaching the photo's bottom, not a counter) and a side wall either side.
    Kitchens are now turned down, and the salesperson places the corners by
    hand with a message saying why.
  - The empty rooms still pass, unchanged.
  - Also tested on a kitchen rendered in code: turned down.
- **Tablet:** tested on a Pixel Tablet emulator (2560 × 1600, landscape). The
  corners screen, suggested corners on an empty room, the kitchen message and
  the 3D view all work. Not yet tried on a real tablet.
- **What would help kitchens:** a corner model trained on our own photos. Each
  quote keeps the photo and its confirmed corners, so the training set grows
  with every job. A depth model alone can't see a wall hidden behind cabinets.

**Trace first, windows and doors found (2026-11-09):**

- **Flow:** photo, then corners (traced), then wall size (filled in from the
  trace, checked with a tape), then windows and doors.
- **Windows and doors found automatically:** MLCommons' DeepLabV3+ (ADE20K,
  Apache 2.0, 9 MB) labels the photo. Windows, curtains and doors on the wall
  are mapped onto the straightened wall and placed as boxes to check.
  - On a real room: 2 of 2 windows boxed on their frames.
  - On a real kitchen, with corners placed by hand: 2 of 3 windows (both
    curtained ones; a small shuttered one was missed).
  - Doors on side walls are left out.
- **Kitchen corners, tried and not shipped:** metric depth (Depth Anything V2
  Metric Small, Apache 2.0) plus the labels, using the room's right angles.
  - Corners found on 6 of 9 kitchens, but only 2 were roughly right, and those
    were too narrow.
  - The metric scale reads rooms 10–20% too deep, so it can't measure the wall
    either.
  - Not in the app. Kitchens keep "place them by hand".
  - Real fix: train on our own collected kitchen photos.

**Our own corner model for kitchens (2026-11-11):**

- **What:** a small model (`assets/models/wall_corners.onnx`, 7 MB) trained
  here, in `tool/wall_corner_training/`, on made-up kitchens and rooms
  rendered in code, whose hidden corners are known exactly.
  - It reads the depth map and the window/door labels the app already
    makes, not the photo.
  - It also says how sure it is.
- **How the app uses it:** only when the depth patches find nothing (a
  kitchen), and only when it expects every corner within 3% of the photo.
  Otherwise "place them by hand", as before.
- **Results:**
  - **Real kitchens:** 3 of 9 now get their corners placed automatically,
    and the 3 look right. Before, none did.
  - **Turned down:** every photo it got wrong, because it was unsure of
    them.
  - **Tablet emulator:** kitchen 09 got the same corners as on the PC; its
    size was prefilled and its window found, with no tapping. Kitchen 02 was
    turned down.
- **Not yet exact:** accepted corners are a few per cent off, and the lean
  check often still asks for a nudge.
- **Measuring it in the field:** quotes now record which method suggested
  the corners (`suggested_by`).
- **Details:** `tool/wall_corner_training/README.md`.
- **Training on the graphics card (same day):**
  - Training now runs on the laptop's RTX 3060: 0.08–0.10 s a step, against
    0.78–0.93 s on the processor.
  - Making the training samples was the slow part; the render was made 4.5×
    faster with identical output, and each sample is also used mirrored.
  - The model was trained on to 30,000 steps (run 2) and shipped: better on
    the made-up set and on the measured empty room, the same decisions on
    all 11 real photos.

**Bottom corners where the floor meets the cabinets (2026-11-11):**

- **What the user found:** on kitchen 09 the traced corners were not
  accurate, and they marked where the corners go.
  - **Bottom corners:** the user marks them where the floor visibly meets
    the cabinets. The model had put them on the hidden line behind the
    cabinets.
  - **Top-left:** about 50 px off.
- **Changes:**
  - **Model:** retrained (run 3) to put the corners where the user would,
    and also to find the hidden wall-floor corners.
  - **App:** shows and drags the corners as marked, but measures from the
    hidden points. Those keep their distance from the bottom corners when
    the corners are dragged.
  - **Updates:** an app update now replaces a cached model. Before, the
    tablet kept running the old one from the cache.
- **Results:**
  - **Kitchen 03:** placed, and its straightened wall stands upright.
  - **Kitchen 09:** now turned down. Run 3 is about 40 px off the user's
    marks there and knows it.
- **What's needed next:** real kitchen photos with corners marked by the
  user. Made-up kitchens alone won't get the corners to within a few pixels.

**The wall's size measured from the photo (2026-11-11):**

- **Before:** the size screen assumed a 2,700 mm ceiling and asked for a
  tape.
- **Now:** it fills in both sizes from the photo, in order of preference:
  - **The worktop:** where the backsplash meets it, about 900 mm up the
    wall.
  - **A door on the wall:** its top, about 2,100 mm up.
  - **Neither found:** the usual 2,700 mm ceiling.

  The corners give the proportions, so one known height gives everything.
  See `lib/features/trace/utils/wall_size.dart`.
- **Checking it:** the salesperson only types if a number looks wrong.
  Typing either size works out the other from the photo; typing both keeps
  both, with the existing warning if they don't fit the photo.
- **Results:**
  - **Real kitchens:** the worktop line was found in all 9, giving ceilings
    of 2,250–3,090 mm (03: 2,700; 08: 2,400; 09: 2,350). Plausible, but not
    checked against a tape.
  - **Doors:** the door top misfired twice (5–6 m walls) and is now limited
    to 55–95% of the way up the wall.
- **Expected accuracy:**
  - Roughly ±5% from worktops that are not exactly 900 mm.
  - The labels' coarseness adds about ±2%.
  - The corners add their own error.
- **Recorded with each quote:** `size_from` (worktop, door, assumed, typed),
  to see how often the estimate gets corrected.
- **When the exact width matters (same day):**
  - **What changed:** when the size came from the photo, the 3D screen lays
    out each layout again with the whole room 5% smaller and 5% larger, as a
    photo's scale error would (walls, ceiling, windows and doors alike). It
    compares what fits: the sink, the hob, tall units and the corner unit.
  - **What the salesperson sees:** if any of those change, a note under the
    layout chips. For example, kitchen 03: "This layout depends on the exact
    width: 140 mm wider, a tall unit fits. Measure the width before
    quoting."
  - **When nothing is said:** at most widths nothing changes. A typed
    measurement turns the check off. See
    `lib/features/layout/width_check.dart`.

**The wall's size from an A4 sheet on the wall (2026-11-13):**

- **Why:** the worktop, door and ceiling cues guess the scale (roughly ±5–7%);
  a sheet of known size measures it.
- **How:** the salesperson tapes an A4 sheet flat on the wall before the
  photo, and on the wall-size screen taps "Measure from an A4 sheet on the
  wall" to put four dots on its corners (`SheetScreen`). The sheet is mapped
  onto the straightened wall; the wall's height is what makes its sides
  210 and 297 mm, either way up and however it's turned. The corners still
  give the proportions. See `lib/features/trace/utils/reference_card.dart`.
- **Checks:** the sheet must be on the traced wall (else it isn't used); if
  its shape on the straightened wall is more than 8% off A4 the screen asks
  to check the dots and the wall's corners; under 3% of the photo's diagonal
  it says the size may be a few per cent off.
- **Expected accuracy:** a dot 4 px off on a 4,000 px photo moves the size
  under 1% (tests). Not yet checked against a tape on real walls.
- **Recorded with each quote:** `size_from: "sheet"` and the sheet's corners
  (`sheet`), to compare with tape measurements later.
- **Next:** find the sheet on the photo by itself, and try it on real walls
  against a tape.
