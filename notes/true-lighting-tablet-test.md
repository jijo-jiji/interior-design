# Testing the true-lighting render on a tablet

**Why:** the true-lighting render (path tracing) has only ever run on a laptop
with software graphics. How fast it is on a real tablet, and whether its
memory use is fine, is unknown. This is a 15-minute test that answers it.

## 1. Get the app on the tablet

**In the tablet's browser (easiest):**

1. On the office laptop, once: `pip install -r backend/requirements.txt`
2. Build and start: `./tool/build_web.sh` (Windows: `.\tool\build_web.ps1`),
   then `cd backend && python main.py`. The server prints its addresses.
3. On the tablet, once: open `http://<laptop-ip>:8000/setup` and install the
   office certificate (the page has steps for Android and iPad).
4. On the tablet, open `https://<laptop-ip>:8443/sales/` in Chrome (Android)
   or Safari (iPad).

**Android app instead:** put the laptop's IP in `lib/shared/config.dart`, start
the server, then `flutter run` with the tablet connected.

Use a tablet you really would use with clients. Charge it and close other apps.

## 2. The test

1. **Room size only** → type a client name → **Continue** → **L-shape** →
   **View in 3D**.
2. Tap the **palette** (Look): doors **Shaker**, backsplash **Subway tile**,
   decor **on**, room **on**, light **Day**.
3. Tap the **camera** icon (pictures). Wait for the two quick pictures.
4. Tap **Make a true-lighting render** with **Standard**. Watch the progress.
   Write down how long it took in total, and read the line under the title when
   it finishes:
   *Light paths traced: N and M samples, in X and Y s. Graphics: …*
5. Look at the pictures at full size (pinch to zoom if you can). Is the wall
   smooth, or is it grainy? Are the oak and the tile light and natural?
6. Repeat with the light on **Evening** (Look → Light → Evening, then the
   camera again).
7. Repeat once with **Fine detail (slower)**.
8. Start a render and tap **Cancel** after a few seconds. Does the app respond
   straight away?
9. When you are done: does the normal 3D view still turn and zoom smoothly?

## 3. What to watch for

- The page **going blank, reloading or the browser tab crashing** during a
  render: that means the tablet ran out of memory. Tell me exactly when it
  happened.
- A message **"This device can't do true lighting…"**: the tablet doesn't have
  what the render needs. Tell me the tablet model and browser.
- The tablet getting **very hot** or the app being **unusable** while it runs.

## 4. What the numbers mean

| Samples reached (per picture) | What the picture looks like |
|---|---|
| 150 or more | clean |
| 50 to 150 | a little grainy, fine for showing a client |
| under 50 | grainy: the tablet is slow for this |

A render stops at its sample limit or its time limit (Standard: 300 samples or
120 s; Fine: 1000 or 300 s), whichever comes first. So a slow tablet always
returns a picture, just a grainier one.

## 5. What to send back

- The tablet model, Android or iPadOS version, and the browser (or "Android app").
- For each run (Day Standard, Evening Standard, Day Fine): the line
  *Light paths traced…*, the total time you measured, and how grainy it was
  (clean / a little / very).
- Whether anything crashed, froze, or fell back.
- A screenshot of the pictures sheet after the first render.

With these I can set the limits for your tablets: raise or lower the sample
and time limits, add a smaller-picture option if it is slow, or make the true
lighting a laptop-only feature if tablets can't do it.
