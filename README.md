# static_trace

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# interior-design

## Running the sales app

The sales app (`lib/`) runs on Android and in a web browser. The office
server (`backend/`) stores quotes and makes the PDFs.

**Android:** set your laptop's IP in `lib/shared/config.dart`, start the
server (`cd backend && python main.py`), then `flutter run`.

**The wall-corner model, once per checkout:** `python tool/fetch_wall_model.py`
downloads it to `assets/models/` (27 MB, checksum-checked; not in git). It
places the wall's corners on a wall photo by itself, on the phone. Without
it the app builds and works the same, but the corners start in the photo's
corners for the salesperson to drag. To install on a tablet, build one APK per
processor type, `flutter build apk --release --split-per-abi`, and install
`app-arm64-v8a-release.apk` (about 83 MB). The single universal APK carries
three copies of the model's runtime and is about 190 MB.

**Browser, served by the office server (recommended):**

```bash
pip install -r backend/requirements.txt   # once; adds HTTPS support
./tool/build_web.sh          # Windows: .\tool\build_web.ps1
cd backend && python main.py
```

The server prints its addresses. It serves:

- `http://<laptop-ip>:8000` for the Android app and the Studio;
- `https://<laptop-ip>:8443/sales/` for the sales app in a browser.

Browsers only allow the camera over https, so `http://…:8000/sales/` is
sent to the https address automatically.

**Each tablet, once:** open `http://<laptop-ip>:8000/setup`, download the
office certificate and install it (the page has steps for Android, iPad,
Windows and Mac). The page shows a green tick once the device is set up.

The server makes its own certificates on first start, in `backend/certs/`.
That folder holds private keys: it is gitignored, so never commit it or
send it. The server certificate renews itself when the laptop's address
changes. The office certificate stays the same, so tablets only need
setting up once. It is limited to local network addresses, so it can't be
used to impersonate other websites.

If the setup page says it couldn't reach the secure address, allow Python
through Windows Firewall on Private networks. Use
`python main.py --no-https` for http only, or `python main.py --dev` for
auto-reload while coding.

**Browser, while developing:**

```bash
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8000
```

Notes for the browser:

- **Camera access:** the camera works over the https address once the
  device is set up (see above). Without that, "Choose from gallery" still
  works, and on a tablet it can open the camera too.
- **Saved designs:** kept in the browser's storage, separately for each
  address. Designs saved on the old `http://…:8000/sales/` address don't
  show up on the https one. Clearing site data deletes the ones not yet
  sent.
- **The 3D view:** runs in an iframe.


## The price list (catalogue)

Every price, size, finish multiplier, benchtop rate, tax rate and layout rule
lives in one place: the **catalogue**, kept by the office server and edited in
the Studio (**Price list** in the header).

- **Designer:** open the Studio, choose *Price list*, change what needs
  changing, and *Save as version N*. Older versions are kept. A cabinet that
  isn't in the list is priced by its width (a price at a reference width,
  plus so much per 100 mm), not a flat figure.
- **Sales app:** takes the latest catalogue when the home screen loads, keeps
  a copy for offline use, and starts on the sample prices shipped inside it.
  A design stays on the version it was opened with; the version is saved on
  the quote, and the office prices the quote with that version, so the PDF
  always matches what the client saw.
- **Office server:** `GET /api/catalog` (add `?version=N` for an earlier one),
  `GET /api/catalog/versions`, `PUT /api/catalog`. To require a key for
  saving, set `CATALOG_ADMIN_KEY` before starting the server; the Studio then
  asks for it. Versions are files in `backend/catalog_store/` (not committed).
- **The shipped sample:** `assets/catalog/default_catalog.json`. After editing
  it, run `python tool/gen_default_catalog.py`; a test fails if the app's
  embedded copy is out of date. **All figures in it are samples** until SS
  Love's designer confirms them (the Studio shows "Sample prices" until the
  box *These are SS Love's confirmed prices* is ticked).
- **One price, three engines:** the server, the sales app and the Studio each
  price a layout. They are checked against the same cases in
  `test/fixtures/pricing_cases.json` (`backend/test_pricing_contract.py`,
  `test/pricing_contract_test.dart`, `frontend/src/pricing.contract.test.ts`).

## Pictures of the design

- **Sales app:** the **camera icon** on the 3D screen takes two pictures of
  the design (front, and from an angle) to show the client on the spot. From
  there: *Send on WhatsApp* (a message with a link) or *Open to save* (the
  page in the browser, where the picture can be saved or shared). Both go
  through the office server, so the tablet needs to be online.
- **A realistic render:** *Make a realistic render* in the same sheet makes
  the two pictures again with soft shadows and darker corners (many frames of
  the view, each lit from a different part of the sky, averaged). It takes
  longer, with a progress bar and *Cancel*. The quote uses the render if the
  design hasn't changed since; otherwise it takes the quick pictures.
- **A true-lighting render:** *Make a true-lighting render* follows light
  paths on the tablet's graphics chip (path tracing), so light really bounces:
  the oak tints the wall beside it, corners darken, the under-cabinet lights
  glow on the tile. It is the closest the app gets to a photograph. It runs in
  the 3D page with no internet. A picture is as clean as the samples it
  reaches: it stops at 300 samples or 120 seconds (*Fine detail*: 1000 or 300),
  whichever comes first, then smooths what noise is left, harder the fewer
  samples it got. It needs a recent device (WebGL 2 with float render targets); on one
  without, the sheet says so and makes the realistic render instead. *Cancel*
  stops it. The library is `assets/3d/pathtracer.min.js`
  ([how it is built](tool/pathtracer/README.md), licences in
  `assets/3d/pathtracer.LICENSE.txt`). After a true-lighting render the sheet
  shows how many samples each picture reached, how long it took and the
  graphics chip. **How fast it is on a tablet has not been measured** (here it
  was only run with software rendering): see
  [the tablet test](notes/true-lighting-tablet-test.md).
- **The quote:** sending a quote carries the pictures. The signed PDF shows
  them under "Your design", and the client's message links a page with them
  (`/pictures/<quote id>`). Pictures are stored in `backend/design_pictures/`
  (not committed). Like the 3D link, the page is reachable from the office
  network.
- **Studio:** *Picture* in the header saves the 3D view as a 2000 px PNG
  (not in Plan and Elevation).

### Finish textures

The 3D page puts wood, stone and painted finishes on the cabinets, worktop and
floor (`assets/3d/textures/`). **They are generated stand-ins, not
photographs of SS Love's finishes**: the folder's README says how to replace
them with real photographs. Choosing a benchtop in the Edit panel now changes
the worktop in the 3D view (the Calacatta and granite choices have their own
look; any other benchtop keeps the style's worktop).

**The Studio's 3D view uses the same files.** `frontend/` builds them into the
Studio bundle (`backend/static/studio/assets/`, committed with the rest of the
build), so replacing a photograph in `assets/3d/textures/` and running
`npm run build` in `frontend/` changes both apps. The Studio draws the oak,
birch and walnut fronts, the quartz, terrazzo, slate, Calacatta and granite
worktops (the benchtop chosen in the Finish tab) and the plank floor, and falls
back on its drawn textures while they decode or if they can't be had. Its
Picture button waits for them. The Studio's cabinet data
(`frontend/src/canvas/finishes.ts`) is checked against the sales app's page
by a test, so the two can't drift apart.

### Changing a cabinet where it stands

**Double-tap a cabinet** in the 3D view (in any mode) and its card opens: the
camera glides round to it, framed above the card, and the card says what it
is ("Floor unit with 2 doors · 600 × 850 × 600 mm"). From the card:

- **Size:** the same unit in the other widths the price list makes (300 to
  900 for a base unit). Its left end stays put (or its right end, if that is
  what fits), so it doesn't have to be taken out and put back.
- **Change to:** another unit in its place: drawers, a sink or hob unit or a
  dishwasher for a base unit; an oven tower or fridge recess for a tall unit;
  a rangehood for a wall unit.
- What doesn't fit (its neighbours, the wall end, a door or a window with its
  clearance are in the way) is greyed out, and the card says how much room
  there is. Neighbours are never moved for you.
- With the price shown, every choice says what it does to the total
  ("+RM 80", "−RM 40", "same price"); while the client sees the design first,
  it doesn't.
- **Move** (50 mm a tap) and **Remove**; the close button takes the camera
  back to where it was.

A single tap only turns the view, so the client can't open anything by
accident. Without a double tap: **Edit**, pick a cabinet, **Change**.
**Undo** and **Redo** in the top bar take back any change to the cabinets: a
layout switched, a cabinet added, moved, resized, swapped or removed.

### Adding a unit: see it first

A unit from the **Edit** tray or the **Appliances** list is not dropped at the
end of the wall any more. Its card opens first ("Add Base 600 · Floor unit
with 2 doors · 600 × 850 × 600 mm") and the 3D view shows it, see-through with
a green outline, where it would go:

- **Size:** its other widths; one with no room on these walls is greyed out.
- **Where:** every free space it fits in, by what is next to it ("At the left
  end · 950 mm free", "Next to Drawers 600 · 1200 mm free", "On the side
  wall · 1100 mm free"). Floor units go where the floor run has room (a
  window above the worktop doesn't count); wall units go where the wall-unit
  band is free (not over a window); tall units need both. The space next to
  the selected cabinet comes first. A unit goes at the start of its space,
  touching its neighbour.
- With the price shown, the card says what it adds ("+RM 340"), and so does
  each size; while the client sees the design first, it doesn't (nor does the
  appliance list).
- **Place it** adds it, and its own card opens so it can be changed or moved
  at once; **Undo** takes it back. **Cancel** adds nothing.
- If there is no room anywhere, the card says so and Place is off.

### Look of the design (doors, backsplash, decor, room, light)

The palette icon on the 3D screen changes how the design is dressed, in 3D
and in the pictures: **doors** (flat, shaker, raised panel; framed doors also
get a cornice on the wall units), **backsplash** (none, subway or hexagon
tile, following the cabinets and stopping at windows), **light** (day, or a
warm evening with the under-cabinet lights on) and **decor** (plates, jars,
plants and the like on the worktop, drawn from simple shapes) and **the room**
(the side walls, a ceiling with downlights, skirting and a wooden floor
around the kitchen, so a picture reads as a kitchen in a room instead of
cabinets on a plain floor; in the evening the downlights are lit too). The
room is cut away from above, so the 3D view stays open, and it steps aside in
the Room and House views of a design read from a floor plan, which show the
plan's own walls. It is saved with the design. **None of it changes the
price**, and the quote PDF and the client's picture page say that the decor
and the backsplash tile shown are not part of the quote and that the door
style and the room are for illustration. If a door style or a tile should
cost more, that needs a price rule from the designer.
