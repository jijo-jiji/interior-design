# Repository analysis & product direction — session summary

Captured 2026-09-19 to 2026-11-02. This is a handoff note for a new session: what was found, what was decided, what's still open, and what to do next.

## 1. What this repo is

"Static Trace" — a sales/design tool for a custom cabinetry business. Four parts:

- **`lib/`** — Flutter mobile app (salesperson field tool). Riverpod, go_router. Three room-capture paths: photo trace (`trace/`), floor-plan calibration (`floorplan/`), template room dial (`template/`). A WebView-hosted Three.js viewer (`assets/3d/index.html`) renders the room and cabinets **locally, fully parametric (`THREE.BoxGeometry`), no GLTFLoader anywhere** — confirmed by code read, this matters (see §4). Closing flow: signature pad, deposit, offline queue (`offline_store.dart` — real file-backed draft queue with sync-on-reconnect, already solid).
- **`backend/`** — FastAPI. `/quote`, `/pdf/{id}`, `/api/projects` CRUD, `/api/catalog`, DXF/cutlist export. Storage is a flat `projects_db.json` (no real DB, no auth).
- **`frontend/`** — React 19 + R3F "Studio" web app (desktop designer workbench). Built output is committed into `backend/static/studio/`.
- **`assets/3d/`** — bundled Three.js + OrbitControls for the Flutter WebView. `assets/3d/models/` and `assets/3d/textures/` (25 `.glb` files, 46 MB) are **untracked and unused by any code** — confirmed via grep, nothing loads them.

Two commits on `main`, no other branches before this session. Only untracked files: the above GLBs/textures and `plan/coohom_workflow_report.pdf` (new this session, not yet committed).

## 2. Pricing — found three disagreeing implementations

- `lib/features/viewer/models/cpq_engine.dart` (Dart, on-device): cabinet base price × style multiplier, benchtop $/m, labour $120/cabinet, window/door allowances, 10% GST, naive 36-month finance estimate.
- `backend/main.py` `/quote` (Python): same base tables, but **no benchtop pricing at all**, no corner-cabinet bucket, no clamp-to-zero.
- `frontend/src/components/JoineryInspector.tsx` (React, web Studio): different formula — flat $450/m benchtop, adds a door-style multiplier the other two don't have, no labour, no obstacle allowance.
- `PUT /api/projects/{id}` trusts client-submitted totals with no server-side recompute — a price-tampering risk if ever exposed to untrusted clients.

**Status: not fixed, deliberately parked** — see §5 (quote question on hold for the client).

## 3. Coohom benchmark (competitor research)

Full report: **`plan/coohom_workflow_report.pdf`** (36 pages, 29 screenshots, built 2026-09-19 against a live free Coohom account). **This file is untracked — not yet committed.** Key findings documented there in depth; summary:

- One linear pipeline: Home → Project → Editor → Render → Gallery → Share.
- **Kitchen & Cabinet is a separate editor** from the general interior one — manufacturer SKU catalog (real codes like `3DB12`...`3DB36`, width-stepped), parametric cabinets (hinge, drawer count/height, door finish, pull style), a "Kitchen AI" dialog (draw cabinet-area rectangle + mark sink/cooktop + Generate, costs AI credits — generation itself never observed, account had 0 credits), and a **Quotation export** ("Cabinet List" template, output never generated — unknown if it carries prices).
- Share = permanent public view-only link by default (expiry/password optional), auto-built client page (hero image, per-level gallery, dimensioned floor plan).
- Free-tier renders are async (minutes-long queue) and watermarked.
- Early in the session I incorrectly stated "no quote feature found" — corrected once the Kitchen editor's Quotation export was located. Report explicitly flags this correction.

## 4. Key architectural finding: stay parametric, drop the GLBs

Confirmed by code read: **both the Flutter/Three.js viewer and the React/R3F `CabinetMesh.tsx` build cabinets entirely from `BoxGeometry` primitives, parameterized by width/height/depth/door-count/etc.** No `.glb` loading exists anywhere in the codebase. The 25 untracked `.glb` files in `assets/3d/models/` are not used.

**Decision: keep the parametric approach, do not switch to GLB models.** Reasoning: for a multi-tenant SaaS, a parametric catalog is a JSON row per module (any width is free); a GLB catalog needs a modeled file per SKU per width — doesn't scale across tenants and is heavy for offline mobile use. GLBs would only make sense later for one-off decorative/signature pieces.

## 5. The pivot: this is not custom software for one client — it's a SaaS platform

Mid-session the user revealed the real context (not an earlier assumption — stated directly by the client):

- The client is an **interior design business owner** (SS Love Cabinet & Furniture, sslovecabinetfurniture.com — full-service: interior design, built-in cabinetry, construction/renovation, architecture, mosque design, CNC/laser custom merchandise). Her site lists real finish materials: **Solid Nyatoh, HMR (engraving), Melamine, Laminated, 4G/5G Glass, Aluminium** — a better finish source than the current `japandi/nordic/industrial` enum in the code.
- Her stated problem: sales cycle is slow because design work happens **after** the sales meeting — client meets her, she must send measurements to a separate designer, wait **3 days** for a design, and any revision costs **another 1–2 days**. This kills momentum and is why deals don't close.
- **She wants a mobile platform that lets a salesperson close in a 15-minute workflow**, in person, with the client.
- **She says (her words, not the user's assumption) every interior-design salesperson has this problem** — so the plan is to build this as a **SaaS platform**: the user builds the software, she markets/sells it. SS Love becomes tenant #1, and her designer's cabinet catalog becomes the seed content for the product.
- Her answers to direct questions:
  - What clients get after 3 days today: **3D models/renders** — clients want to "try and test," asking things like "is this cabinet suitable?", "how about this design?" → confirms the product is a **comparison tool**, not a single polished output. Showing 3 variants (A/B/C) fast is more valuable than one perfect design.
  - **Pricing happens only after the client likes the design** — so pricing is not in the 15-minute critical path; the three-way pricing disagreement (§2) can stay parked without blocking this work.
  - **She has no clear idea how many standard styles/layouts her designer could pre-build** — open item, needs a direct conversation with the designer.
  - **Field conditions are a critical constraint: salespeople sometimes work in buildings with no wifi / weak signal.** This is the single most important differentiator vs. Coohom, which is cloud-only (render queue took minutes in testing, dead with no connectivity). The app's existing local-WebView-render + offline draft queue (`offline_store.dart`) is a real architectural advantage, not a workaround — the whole build should be designed around "must work in airplane mode."
  - The user's own read of their Flutter code: **measurement + local 3D room generation is the solved part** (confirmed by code read in §1) — client has already approved this concept. The gap is going from an empty room to a **filled cabinet layout** without manual one-by-one placement (drag+snap exists in `assets/3d/index.html:1082` but is manual, not generative).

## 6. Proposed architecture (walked through with user, not yet built)

1. **Deterministic layout generator** (no AI/ML needed) — new `lib/features/layout/layout_generator.dart`, feeding the existing `placed_cabinets` payload shape the viewer already consumes (`viewer_screen.dart:50`+). Algorithm sketch: place anchor modules (tall unit, sink under window, cooktop ≥600mm from sink) → greedy-fill gaps from catalog's real widths → mirror for wall cabinets, skip window/hood over cooktop → emit module list with x-positions. Rules (door swing, corner handling, min aisle, filler panel minimum) must come from the real designer, not guessed.
2. **Variants, not one output** — same room generated 3 ways (Value/Balanced/Premium, different module-selection weighting) so the salesperson can swipe A→B→C live with the client — this directly answers the "is this suitable / how about this" behavior pattern.
3. **Catalog as tenant-scoped data** — replace all hardcoded price/style/module tables (§2) with: Tenant → Catalog version → Modules (SKU, family, widths[], dims, type, price, rules) + Finishes (SKU, texture, price modifier) + Styles. SS Love's real catalog becomes the seed/template for other tenants.
4. **Offline-first sync** — catalog pulled/cached with versioning (works stale); quotes/designs use the existing local-queue pattern, extended; client-share link is the one piece that needs signal, with an on-device fallback (show on tablet, send link later once online).
5. **Build order proposed**: (1) generator for single-wall + L-shape kitchen only, using placeholder catalog data, to get a demo working end-to-end fast; (2) catalog-as-data, kill hardcoded lists; (3) variants + finish picker; (4) multi-tenant backend + designer catalog publisher; (5) pricing — only once the client's pricing-workflow questions are answered.
6. **Scope warning**: do not attempt to cover SS Love's full service list (architecture, mosque design, CNC merchandise) — start with built-in cabinetry only (kitchen, wardrobe, TV unit) since those are repeatable/rule-friendly; items like facade/mosque design will never auto-generate well.

## 7. Full "what we need from the client" checklist (delivered to user this session)

Organized by priority — full detail was given in chat; key blocking items:

**Blocks the generator code (get first):**
- Real module list per type (base/wall/tall/corner/filler/drawer-bank/open-shelf) with available widths, depth, height, door/drawer options, custom-width limits — for kitchen **and** wardrobe/TV-unit/vanity if sold.
- Standard dimensions (base/wall/tall heights, counter thickness, toe-kick, wall-cabinet mounting height).
- 3–5 standard layout patterns per common wall length (2.4m/3m/4m), ideally from **5–10 real finished projects** with floor plan + final layout.
- The designer's unwritten rules: sink-vs-window placement, min sink-to-hob distance, tall-unit placement, min aisle width, door-swing clearance, corner handling, smallest filler panel, appliance clearances/hood height.
- Standard appliance sizes (fridge, hob, oven, sink, hood).

**Needed next (finishes, workflow):**
- Full finish/material list with codes and swatch photos (starting point: Solid Nyatoh, HMR, Melamine, Laminated, 4G/5G Glass, Aluminium — already public on her site).
- Style count + one photo per style; 10 best finished projects with photos/dimensions.
- Current sales process step-by-step: what's collected at first visit, what the 3-day deliverable actually contains, what clients most often ask to revise (tells us what must be live-editable), what info the designer needs from a measurement (ceiling height, plumbing/electrical points, beams/columns).
- Field conditions: devices used, typical site types, meeting length, salesperson count, language/tech comfort.

**Pricing (ask only when pricing conversation happens — not blocking):**
- Current pricing method (per metre/module/material tier), one real recent quote as an example, price ranges by style/material, deposit/tax/discount rules, who can edit prices, quote validity period, when in the conversation price is revealed.

**Before selling as SaaS (business/partnership — flagged as needing her input + likely legal advice, not something to decide unilaterally):**
- Target customer profile, her pricing model for the SaaS itself, marketing timeline/expectations.
- **Who owns the catalog data and customer relationships** if other firms join — flagged as a real open question, not advised on.
- Whether SS Love's catalog is exclusive or shared across tenants.
- Pilot period/feedback commitment.
- **PDPA (Malaysia) data-protection obligations** — the app will hold client names, addresses, signatures. Flagged to get legal advice, explicitly not something I advised on.
- A written partnership agreement — flagged as needing a lawyer.

**Pilot logistics:**
- Designer availability (half a day/week during build), 2-3 real client meetings to field-test, 5 completed real projects with measurements to replay/validate the generator against, one named decision-maker at her company.

**The 3 items flagged as most urgent ("this week")**: (1) designer's module list, (2) 5 finished projects with floor plans, (3) one real quote example.

User asked for this as a one-page checklist/spreadsheet to send the designer directly — **done 2026-11-02**: `notes/SS-Love-designer-checklist.xlsx` (see §10).

## 8. Open decisions / questions, unresolved as of this note

1. ~~**Room type to prototype first**~~ — **decided 2026-11-02: kitchen** (single wall + L-shape). Built, see §10.
2. **The 25 untracked `.glb` files** — unclear why they were added if nothing loads them; not confirmed whether user intended to switch rendering approach. Current recommendation: keep parametric, don't use them (§4), but user's original intent for downloading them is unconfirmed.
3. ~~**Where to start building**~~ — **decided 2026-11-02: generator with placeholder data first.** Built, see §10.
4. ~~**The checklist/spreadsheet deliverable**~~ — **done**, see §10. Not yet sent to the designer as far as this note knows.
5. **Partnership/data-ownership terms** — entirely open, flagged as the client's and a lawyer's call, not something to resolve in code.
6. **Pricing reconciliation (§2)** — deliberately not touched; will need resourcing once the client answers the pricing-workflow questions.
7. **`plan/coohom_workflow_report.pdf` and `assets/3d/models/` + `assets/3d/textures/`** — still untracked in the repo as of this note. Not committed in this session (this notes file is the only thing being committed/pushed per the current instruction).

## 9. Suggested next steps for a new session

1. If the client has sent back the module list / 5 projects / sample quote, start there — validate the generator approach against real data before writing speculative rules.
2. Otherwise, build the layout generator with clearly-labeled placeholder catalog data (kitchen, single-wall + L-shape only) so there's a working demo to show the client while her answers are pending.
3. Decide whether to commit `plan/coohom_workflow_report.pdf` and clean up / .gitignore the unused `assets/3d/models/` and `assets/3d/textures/` (46MB, untracked, confirmed unused).
4. Produce the one-page checklist/spreadsheet for the designer if not already sent.
5. Do not start on pricing reconciliation or multi-tenant backend work until the §7 blocking items come back from the client.

## 10. Session 2026-11-02 (cloud session) — what was built

User chose: build **both** the checklist and the generator; **kitchen** first; checklist **bilingual EN + BM**.

**Designer checklist** — `notes/SS-Love-designer-checklist.xlsx`. Start sheet (purpose, how to fill, the 3 urgent items, progress tracker, "working together" questions) + 8 sheets: modules, standard sizes, layout rules + standard layouts per wall length, appliances, finishes (pre-filled with the six materials from her site), styles & past projects, sales process & site conditions, pricing (only the sample quote marked urgent). Yellow = fill in, grey = example row. Business / partnership / PDPA questions were deliberately left out — those are for the owner (and a lawyer), not the designer. The BM text should be checked by a native speaker before sending.

**Kitchen layout generator** — `lib/features/layout/` (pure Dart, no Flutter imports, runs offline on-device):
- `kitchen_catalog.dart` — **all placeholder numbers in one place** (module widths, heights/depths, wall-cabinet mounting height, and rules: sink↔hob ≥ 600, ≥ 300 worktop each side of hob, ≥ 300 between sink and tall unit, fillers 25–150, door clearance 50, etc.). Each rule maps to a question in the checklist; swapping in the designer's answers is the only change needed.
- `kitchen_layout_generator.dart` — deterministic: split walls around doors/low windows → corner unit for L → tall units at outer ends → search sink (under window first) + hob positions → fill gaps with catalog widths via DP (leftover → filler) → score plans, keep best → fill the wall-cabinet band (aligned with base modules where possible; nothing over hob/window/door/tall). Three variants: **A Value** (doors only, no tall), **B Balanced** (1 tall, drawers between sink and hob), **C Premium** (up to 2 talls, drawer banks). Drops talls, then the hob, when a wall is too short, and says why in `warnings`. ~3–35 ms per room for all three variants on a desktop VM.
- Galley/studio shapes are not generated yet (falls back to the main wall with a note). Wardrobes not started.
- Tests: `test/kitchen_layout_generator_test.dart` — rule invariants (no overlaps, clear of doors/windows, hob/sink/tall rules, wall-cabinet rules, full coverage) across single wall / L / door / low window / short wall / low ceiling, plus a sweep of every wall length 1800–4800 mm in 5 mm steps.

**Viewer wiring** — `viewer_screen.dart` generates A/B/C when the viewer opens; an empty room starts on B; an "Auto layouts" bar (labelled "sample catalog") switches variants live; "Clear" empties the room; manual module tray still works on top. `assets/3d/index.html`:
- **Bug fix**: `buildWall()` referenced an undefined `parsed` variable, so `placed_cabinets` (restored drafts) and `style_archetype` never loaded — threw inside `loadScene`'s try/catch. Now uses `scenePayload`.
- L-shape return wall moved to sit **outside** the measured main-wall width (it used to overlap the first 150 mm), so both measured lengths are usable interior.
- New `spawnGeneratedCabinet()` renders any width/kind (door pairs, drawer lines, black-glass hob, steel sink, no worktop on talls), rotates return-wall cabinets, and `replaceCabinets()` swaps whole layouts. Return-wall units are tap-to-select only (drag only slides along the main wall).
- Flutter now handles the `cabinet_moved` event so dragged positions are saved.

**Known gaps / not done:**
- Pricing untouched (still parked). Generated module types like `base_drawer_600` / `filler_base` fall back to the $300 default in **both** the Dart CPQ and backend `/quote`, so the odometer and quote are placeholder numbers — fillers are currently charged as cabinets.
- Not tested on a real device / WebView — verified with unit tests, `flutter analyze`, and headless-Chromium renders of the transformed `index.html`.
- Items in §8.2, §8.5–7 still open.

**Next steps:** send the checklist; when answers return, replace `KitchenCatalog.placeholder` / `KitchenRules.placeholder` and replay the 5 real projects through the generator to compare against what was actually built; then catalog-as-data (tenant-scoped) and pricing.

**Update (same session):** the full checklist felt too long to send cold, so `notes/SS-Love-designer-quick-questions.xlsx` is **what goes to the designer first**: one page with 3 things to send (5 kitchen drawings, standard sizes list, one quote) and 6 quick questions. Most of the remaining rules can be read off the 5 drawings. The full checklist is now the user's own interview guide for a later 30-minute chat, not something to send.

**Update:** user asked the owner (WhatsApp) for client room photos, her usual floor plans, and her designer's 3D assets for the demo. The one-page sheet now also asks for 3D files (models, finish textures, renders; Drive link or WhatsApp *document* so they aren't compressed) and whether those models are their own or downloaded/bought — matters before using them in a product shown to other firms. Note: the viewer is Three.js and parametric (§4); finish **textures** can be mapped onto the generated cabinets directly, but SketchUp/3ds Max models would need converting to glTF and a loader added.

**Update:** one-page sheet item A5 now asks for client room photos from site visits — ideally of the same 5 kitchens before work started, whole walls straight on (no people/addresses). Purpose: run them through the app's photo-trace flow, generate layouts, and compare with the drawings of what was actually built.

**Update:** one-page sheet restructured to one request per row (user asked): A. drawings/photos/documents (5 rows: floor plans, final layouts, room photos, standard sizes, quote), B. 3D assets for the demo in its own section (4 rows: cabinet models, appliance models, finish textures, renders), C. 8 quick questions (counter height and wall-cabinet height split). Portrait A4, one page; "Don't have" added to the Sent? dropdown.

## 11. Session 2026-11-03 — 3D viewer look (assets/3d/index.html)

User installed plugins: frontend-design, Very Good AI Flutter, parallax-threejs, 3D CAD Converter (the converter's tool needs Windows `cmd`, so it only runs on PC-JAWA, not in a cloud session). User chose to start UI/UX work with the 3D viewer's look.

- **One cabinet builder** for manual, restored and generated cabinets: recessed plinth, carcass, 18 mm fronts with 3 mm shadow reveals, drawer stacks (drawer/hob units), stacked tall doors, stone worktop with front overhang, L-shaped corner unit (was a 900×900 box that filled the inside corner), sink with worktop cut-out + steel basin + tap, black-glass hob with burners + chimney hood, warm LED strip under wall cabinets.
- **Style presets now mean materials** (`STYLE_FINISHES`, keyed by the same ids Flutter/CPQ use): Japandi light oak + brass bars + warm quartz; Minimalist matte charcoal handleless (finger groove); Nordic sage + birch tall + nickel knobs + terrazzo; Industrial walnut + graphite wall cabinets + black bars + dark slate. Shared materials; style change rebuilds handles.
- Textures are procedural canvas (wood grain, stone, floor planks) with metre-based UVs — offline, no image files; swap in the designer's textures later.
- Lighting: baked procedural environment map (reflections + soft fill), hemisphere + one shadowed key light, sRGB output.
- **Render on demand** (`invalidate()`): no redraws while idle — matters for phone battery/heat.
- **Bug fix**: `window.spawnCabinet` / `window.removeSelectedCabinet` were redefined at the bottom as wrappers that called themselves → "Maximum call stack size exceeded"; the module tray's add/remove never worked (present since the first commit).
- Verified in headless Chromium (all 4 styles, single + L, manual add/remove, style switch, 10× layout swap with no geometry leak, draft restore, zero idle frames). Not yet checked on a real phone — check frame rate on a low-end Android.

## 12. Session 2026-11-03 — sales app review + fixes 1 & 2

Design review of the Flutter sales flow (in chat): biggest issues were client-visible AUD/GST, price shown immediately, nothing saved unless signed, sales jargon on a shared screen, and invented commercial terms. User approved fixes 1 and 2:

**Fix 1 — client-safe screens**
- `lib/shared/sales_config.dart` (brand, currency "RM", tax label "SST") + `money.dart` (`formatMoney` → "RM 18,450"). Tax *rate* is still `CPQEngine.gstRate` (10%) — placeholder; confirm SST treatment with the owner/accountant.
- Removed: "Sales Closer", "Start Sales Pitch", "Avg Close 4m 12s" hero card, developer footer, "Priority Locked", 30-day price guarantee, fixed $250 "slot" deposit, 36-month finance figures. One action name: "Quote".
- Viewer: price hidden until "Show price" (or opening the price breakdown); "Hide price" to hide again.
- Plain-language copy on home, floor plan ("Set the scale"), room size, trace ("Mark windows & doors"); all 3D CTAs say "View in 3D".

**Fix 2 — never lose a design**
- Home → "New client" asks name (+ optional phone) before measuring (`consultationProvider`, quote number assigned up front; "Skip for now" allowed).
- Viewer auto-saves to the phone ~0.8 s after every change (variant, add/remove/move, style) and on leaving; one record per quote number.
- Statuses (`lib/shared/project_status.dart`): Draft / Quote sent / Deposit paid. Drafts stay on the phone and are never auto-sent; quotes/orders sync. Clients tab filters: All, Drafts, Quotes sent, Deposit paid, Waiting to send.
- Quote sheet: "Save & send quote" needs only the name (signature optional); "Confirm order" needs deposit amount (typed by salesperson) + signature.
- Sending only removes the phone copy if the server returns 200/201 (before: any response, even an error, deleted it).

**Process notes**
- Repo was run through `dart format` once (separate commit) because the VGV plugin's hook formats every edited Dart file.
- The VGV plugin blocks `flutter test` in favour of its MCP test tool, which can't start in cloud sessions ("Executable not found: stdio"). User authorised running `flutter test` directly for this session: 58/58 pass. Screens rendered via a temporary test harness (not committed; fonts bundled temporarily).
- Not done (from the review): fix 3 (declutter viewer: duplicate Quote button, module tray behind "Edit"), fix 4 (type/colour tokens, contrast, 48dp targets — incl. the A/B/C bar's tiny "Clear"), fix 5 (home simplification beyond copy), galley/studio in template, trace-screen debug text, i18n (BM/Chinese).

**Fix 3 — decluttered 3D view (same session)**
- One "Quote" button (bottom bar); app bar now has only the client's name and a "Full view" toggle that hides every control (floating "Show controls" brings them back).
- Bottom panel has two modes: **Layouts** (A/B/C + "Edit") and **Edit** (add-cabinet tray, "Remove <cabinet>" for the selected one, "Clear all" with Undo, "Done"). Replaces the always-visible module tray and the tiny "Clear" link.
- Cabinets are locked outside Edit: in the app, touches on the 3D only orbit (`setEditMode` in index.html), so showing the client around can't move anything. In Edit, tap selects and drag moves.
- New: removing a single cabinet in the app (the page's own remove bar is hidden in app mode, so before this only "clear everything" existed). Page now sends `cabinet_selected` / `cabinet_deselected`, and `cabinet_moved` only when it actually moved (every tap used to send one).
- A manual change unselects A/B/C and the panel says "your changes".
- Price row: "Show price" shrinks instead of overflowing at large text sizes; price breakdown opens from the price ("Details"), not from a separate app-bar icon.
- Tests: `test/viewer_screen_test.dart` + `test/helpers/fake_webview.dart` (fake WebView that records JS calls and can send page events). 63/63 pass via the VGV plugin's own test tool, which connected after `dart` and Very Good CLI were put on PATH.

**Fix 4 — type scale, contrast, touch targets (WCAG 2.2 AA, Android + Web)**
- Font bundled in `assets/fonts/` (Plus Jakarta Sans, OFL) and `google_fonts` removed: the app used to download its font at runtime, so offline first launches fell back to the system font. Run `flutter pub get` locally (lock file deliberately not regenerated here — this container's newer Flutter would have bumped the SDK floor to Dart 3.11).
- `lib/shared/theme.dart`: `AppTextStyle` scale (min 12), full `ColorScheme`, button/input/app-bar themes with 48dp minimums, `context.textTheme` / `context.colors`. All 76 inline `TextStyle`s migrated; no `fontSize`/`fontWeight` left in widget code.
- Contrast: danger `#A94444`, secondary text `#6E5F52`, taupe text `#7D6248`, form-field outline `#9C8E80` (3.2:1); removed faded-opacity text; leftover dark-theme panels (floor plan dimensions, room-size tabs/badges) moved to the light palette.
- Tap targets/semantics: home tabs, trace Window/Door (now real buttons), style pills, A/B/C chips, camera shutter (labelled), shape tabs, Back tooltip.
- Text scaling: rows that overflowed at 2x now wrap/shrink. Trace screen first-frame crash (`clamp(50, 1)`) fixed.
- `test/accessibility_test.dart`: per screen — 48dp + labelled targets, pixel contrast scan, no overflow at 2x, no button label overriding its colour; theme contrast/min-size checks. 95/95 via the VGV plugin's test tool.
- Open AA findings (not fixed): 2.5.7 dragging alternatives — trace wall-edge lines and window/door boxes, floor plan pins, and moving cabinets in Edit mode are drag-only (signature is exempt). Web: the app imports `dart:io` (HttpClient/File) and cannot build for web at all yet. Spacing tokens / dark theme not done; non-text colours still read from `AppTheme` constants.

## 13. Session 2026-11-04 — no-drag alternatives (WCAG 2.5.7) + capture-flow polish (fix 5)

**Part A — everything that was drag-only now also works with taps, arrows or typed sizes** (commit 265dc37)
- `lib/shared/widgets/nudge_buttons.dart`: shared 48dp labelled arrow buttons.
- Trace screen is two steps in a fixed-height bottom panel, so the photo never shifts between steps.
  - Step 1, "Line up the wall edges": pick Ceiling / Floor / Left / Right, then tap the photo or use the arrows. Uses `WallSetupNotifier.moveEdge`, which keeps edges 5% apart. Edges now start 8% inside the photo instead of on its border.
  - Step 2, "Mark windows & doors": add window (1200 × 1000, sill 1000) or door (900 × 2100). Each item is listed as a chip that opens the editor.
  - The debug "Scale: 1mm = … px" readout is gone.
- `lib/features/trace/widgets/obstacle_editor.dart`: the shared "Window 1 · size and position" dialog (width, height, from left/right wall, from floor/ceiling, Remove). Boxes are labelled for screen readers; their remove button is 48dp.
- Floor plan:
  - The room box (its left edge could never move) is replaced by **Wall start (1) / Wall end (2)** marks. Wall width = distance(1, 2) ÷ (A–B px ÷ A–B mm).
  - Marks are placed by tap or arrows, and sit inside the `InteractiveViewer`, so they stay on the plan when zooming (before, zoom left them misaligned).
- 3D Edit mode:
  - **Pick** (previous/next cabinet) and **Move** (50 mm) buttons, backed by the new page functions `selectAdjacentCabinet(dir)` and `nudgeSelectedCabinet(dxMm)` in `assets/3d/index.html`.
  - `cabinet_selected` carries a `movable` flag; corner (return-wall) units say they can't move yet.
  - Checked in headless Chromium on the L-shape layout: 9/9 checks.
- Bug fixed: the trace screen rebuilt every frame, because the canvas size was re-stored after each layout even when unchanged.

**Part B — fix 5**
- **Wall size screen:**
  - Plain copy ("Measure the wall… in millimetres").
  - Thickness field and px-ratio preview removed; depth stays 150.
  - Range checks catch cm/m slips: width 500–15000, height 1800–5000.
  - Button: "Next: line up the photo".
- **Camera:** errors in plain words with a Gallery action (never the raw exception), and a Back button (there was none). `availableCameras()` failures are now caught.
- **Room size:** Galley and Studio hidden until the generator supports them (they silently laid out the main wall only); labels in sentence case.
- **Home:** a "Continue <client>'s design · Draft · saved 10 min ago" card for the newest local draft (`timeAgoLabel` in `lib/shared/labels.dart`).
- **Tests:** 119/119. New files: `trace_screen_test`, `floorplan_screen_test`, `capture_flow_test`. Additions to existing files: viewer Pick/Move, home Continue card, and accessibility cases for the camera screen and trace step 2.

**Web build (planned, not started)**
- **Blockers:** `dart:io` in 5 files. `HttpClient` in intake hub, viewer and offline_store; `File` + path_provider in offline_store; `Image.file` in trace and floor plan. `webview_flutter` has no `runJavaScript` on web.
- **Needed:** `package:http`; `shared_preferences` for offline_store (with a one-time move of the Android file); `XFile.readAsBytes` + `Image.memory`; a `SceneBridge` (WebView on Android, `HtmlElementView` iframe + `postMessage` on web).
- **Risk:** adding packages changes `pubspec.lock`, so versions must be pinned to the local Flutter.
- **Decide first:** whether the Flutter app must run on web, or the React Studio / standalone 3D page covers web demos.

## 14. Session 2026-11-04 — the sales app runs in a web browser

**How to run it:** `./tool/build_web.sh` (or `tool\build_web.ps1` on Windows) builds into `backend/static/sales/`, which is gitignored. The office server now serves it at `http://<server>:8000/sales/`, and the app talks to the server it was opened from. For development: `flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8000`. Details in README → "Running the sales app".

**What changed (Android behaviour is unchanged)**
- **Dependencies:** `http` and `web` are now direct dependencies. Both were already in `pubspec.lock` as transitive packages at the same versions, so only their `dependency:` lines changed (edited by hand; nothing re-resolved).
- **`lib/shared/platform/`:** one API each, with an Android file and a browser file chosen by conditional export.
  - `api_client.dart`: `package:http`, used for all server calls. It returns null when the server is unreachable.
  - `local_store`: a file on Android (same file name, so existing designs carry over), `localStorage` in the browser.
  - `photo_image`: `Image.file` on Android, `Image.network` for `blob:` URLs in the browser.
  - `pointer_shield` and `photo_flip`: see the browser-specific fixes below.
- **`lib/features/viewer/scene/`:** `SceneBridge` is a WebView on Android and an `<iframe srcdoc>` in the browser.
  - The iframe and the app talk over `postMessage`, tagged with a per-bridge id.
  - A script injected into the page defines `StaticTraceChannel`, reports when the page has loaded, and runs only calls that come from the parent window.
  - `index.html` is unchanged.
- **Routes:** screens that need a photo or a design passed from the previous screen go home on a reload or a typed URL, instead of crashing.
- **Web shell:** `web/` folder (title "SS Love", brand colours); `.metadata` gained a web entry.

**Browser-specific fixes found by testing**
- **Clicks on controls over the 3D view were lost.** An iframe swallows pointer events, even under Flutter buttons. Fixed with `PointerShield`, an invisible div behind each control over the 3D view (the `pointer_interceptor` technique, written in-house because that package isn't in the lock file). The iframe also ignores pointer input while a sheet or dialog is open, or while the Undo message shows.
- **Browser camera photos were mirrored.** `camera_web` mirrors photos from any camera that isn't reported as the back camera, which would swap windows left and right. `photo_flip` turns them back after capture.
- **The Continue card couldn't be opened by a screen reader.** It now has a tap action, and a test checks it.

**Verified**
- **Flutter tests (VM):** 119/119.
- **Analyzer:** no new notes.
- **Browser, headless Chromium against the real server** (scripts in the session scratchpad, not committed):
  - Main flow, 18 checks: name → room size → 3D in an iframe → style → Edit / Pick / Move → auto-saved draft in `localStorage` → quote POSTed and stored on the server → reload on `/#/viewer` goes home.
  - Real mouse with the accessibility tree off, 13 checks: drag to orbit; Edit over the 3D view; click and drag a cabinet; Move; Clear all → Undo; typing in the quote sheet and sending.
  - Photos, 12 checks: floor plan upload → measure → 3D; fake camera → wall size → trace → window → 3D; reload → Continue card → 3D.
- **Build:** release `flutter build web` takes about 60 s, output 42 MB (CanvasKit included for offline use). The WebAssembly dry run passed.

**Still to know**
- **Camera:** the browser camera needs `https://` or `localhost`. On plain-`http` LAN addresses, use the gallery picker, which can open the camera on tablets. Serving over https would need a certificate on the office server.
- **Browser storage:** designs live in that browser's storage; clearing site data deletes unsent ones.
- **Not covered by these checks:** a real iPad or Android tablet browser (only Chromium was tested); pinch-zoom inside the 3D view on touch.

## 15. Session 2026-11-04 — HTTPS on the office server (camera in the browser)

**Why:** browsers only allow the camera on `https://` or `localhost`.

**How it works** (`backend/office_https.py`; `cryptography` added to `requirements.txt`)
- **Two servers:** `python main.py` runs http on 8000 (Android app, Studio, `/setup`) and https on 8443 (the browser sales app). `http://…:8000/sales/` redirects (307) to the https address; the API stays on http for the Android app. Flags: `--no-https`; `--dev` keeps the old auto-reload, http-only mode.
- **Own certificate authority:** on first start the server creates an office CA (10 years) and a server certificate for `localhost`, the computer name, `<name>.local` and its private LAN IPs.
- **Renewal:** the server certificate (397 days) renews on start when it nears expiry or the IP changes. The CA stays, so tablets are set up once.
- **Name constraints:** the CA is limited (critical) to private IP ranges, `localhost`, `*.local` and the computer name, so even a leaked CA key can't impersonate real sites. Names the CA doesn't cover (e.g. after renaming the laptop) are left out of the server certificate, so IPs keep working.
- **Files:** `backend/certs/`, gitignored (private keys).
- **`/setup` page** (opened over http):
  - CA download (DER) and install steps for Android, iPad/iPhone, Windows and Mac.
  - The CA fingerprint.
  - A live check: a green tick when the device trusts the server, a "not set up yet" message when it doesn't, and a firewall hint when the secure port doesn't answer within 6 s.

**Verified**
- **`backend/test_office_https.py`, 10 tests:**
  - every local name and IP verifies against the CA;
  - Apple's limits are met (≤ 825 days, serverAuth, RSA 2048);
  - a certificate the CA signs for `www.maybank2u.com.my` / 8.8.8.8 is rejected;
  - public IPs are left out;
  - a new Wi-Fi IP renews the server certificate but keeps the CA;
  - a renamed computer still works by IP;
  - the routes: setup page, DER download (and the key is never served), and the `/sales` redirect.
  - The existing `test_studio.py` still passes (18/18 together).
- **Live server, with curl and `openssl verify`:** the chain is OK, untrusted clients are refused, `/sales` redirects, and Ctrl+C stops both servers cleanly.
- **Chromium, 9 checks:** one browser trusts the CA through an NSS DB; the address is `vm.local` mapped to 127.0.0.1, so it isn't treated as localhost.
  - Trusted: the setup page shows the tick; `http /sales` lands on https; it's a secure context; projects load; the fake camera starts and a photo is taken.
  - Untrusted: the setup page says not set up, and https fails with `ERR_CERT_AUTHORITY_INVALID`.

**Not verified here:** real Android or iPad certificate installation; the steps follow each platform's standard flow, and the Android path can differ by brand ("search Settings for CA certificate").

## 16. Session 2026-11-04 — PR #1 merged locally + Studio UI/UX

**PR #1** (DwZukii, `feat/studio-ui-pricing-contract-myr`): the user chose "merge #1 first".
- Merged into this branch locally (commit "Merge PR #1 …"); not pushed until #1 lands on main.
- Conflicts were resolved keeping both sides:
  - 3D page: PR #1's six appliances are drawn by this branch's builder.
  - Viewer: this branch's layout, with PR #1's benchtop picker, appliance menu, "Send to WhatsApp" and "Open proposal" added back.
  - PDF delivery made web-safe: in memory via package:http, and the browser's own PDF viewer on the web.
  - `pubspec.lock` = PR #1's lock (Flutter ≥ 3.38) with google_fonts removed and http/web marked direct.
- `git rerere` recorded the resolutions.

**Studio** (`frontend/`, built into `backend/static/studio/`):
- **Same kitchen as the sales app:**
  - `canvas/cabinetBuilder.ts` is a TypeScript port of the sales app's cabinet builder: finishes, fronts, handles by style, worktops, sink, hob, appliances, corner unit.
  - `layout/model.ts` handles the sales app's records: centre-from-wall-centre `x_mm`, side-wall `offset_mm`, kind, mounting height, generated sizes.
  - Studio saves write both conventions. Before this, positions from the tablet were misplaced, saves corrupted them (and the DXF export), the side wall was ignored and only "wall_600" hung on the wall.
- **Views:** Plan (top-down, orthographic, wall units hidden) and Elevation (main wall, orthographic), each with dimension lines in mm; every view frames the whole kitchen; "Fit to screen".
- **Layout:**
  - A toolbar row replaces the dock that covered the 3D view: cabinets, an Appliances menu, undo, Fit, and an always-visible total.
  - Panel tabs: Room (shape, sizes, side-wall length) / Finish / Cabinets (a keyboard-selectable list) / Price.
  - Fits 1280×720.
- **Brand and wording:** "SS Love Studio"; plain labels; statuses Draft / Quote sent / Deposit paid, with filters as in the sales app; text ≥ 12 px.
- **Room:** real windows and doors from the measurements; the invented side-wall window is removed.
- **Rendering:** PMREM room environment, so steel and stone reflect.
- **Saving:** keeps the stored wall (thickness, side-wall length).

**Backend fixes found on the way:**
- `PlacedCabinet` now keeps extra fields (kind, run, offset_mm, mount_mm, generated). It was dropping them from every quote.
- `_normalize_project` keeps all fields and computes the Studio's `x` from the real wall width; it used to assume a 3.6 m wall.
- Tests: `backend/test_layout_records.py` (3).

**Verified:**
- Studio: vitest 19 (including the model round-trip); tsc clean; oxlint shows only one older warning.
- axe-core WCAG 2.2 A/AA: 0 violations across six Studio states (one contrast issue fixed with a new `clay-ink` token).
- Browser functional test, 14 checks: keyboard add/move/delete/undo, appliance menu, wall resize, views, and a save round-trip that moves nothing.
- Cross-app: a Studio-saved L-shape opens in the sales app with all 14 cabinets at the same positions.
- Backend: 21 tests plus the pricing contract.

**Open, needs the client:** generated sizes that aren't in the catalogue (base_450, wall_900, base_hob_600, fillers…) are priced at the RM 300 fallback by all three engines, fillers included. A real rule needs SS Love's catalogue.

## 17. Session 2026-11-06 — the catalogue module (prices, sizes and rules as data)

**Why:** the prices, module sizes and layout rules were typed into three codebases (server, sales app, Studio) and the 3D page. Any new price meant a code change in each, and a size that wasn't listed was priced at a flat RM 300. Now there is one **catalogue**, versioned on the server, edited by the designer.

**One document, three readers**
- **`assets/catalog/default_catalog.json`:** the sample catalogue.
  - Modules (type, name, size, price), families (a prefix such as `wall_` with its price rule, installation, worktop and how the 3D view draws it), finishes, benchtops, installation per module, window/door deductions, SST, and the layout generator's widths, sizes and rules.
  - Every number is a sample (`is_placeholder: true`) until the designer confirms it.
  - The server seeds from it, the Studio imports it, and the sales app embeds it as `lib/features/catalog/default_catalog.g.dart` (generated by `tool/gen_default_catalog.py`; a test fails if it goes stale).
- **Price of one module:** its own price if it is a listed module; else its family's rule, `price at reference width + (width − reference) ÷ 100 × per 100 mm`; else the "unlisted module" price. Then the finish multiplier, rounded to the sen. Longest prefix wins (`base_sink_` beats `base_`).
- **Sample rule:** RM 40 per 100 mm for every family, worked back from the two base prices. A stand-in, like the rest.
- **Installation:** per module whose family carries it. Fillers don't (placeholder decision; the designer can change it).

**Server** (`backend/catalog.py`, `main.py`)
- A validated model (strict: unknown fields are refused, with the place named), a store of every version (`backend/catalog_store/`, gitignored; atomic writes; recovers from a damaged current file) and the pricing function.
- `GET /api/catalog` (`?version=N`), `GET /api/catalog/versions`, `PUT /api/catalog` with the whole document plus `base_version`: 409 if stale, 422 listing each bad value. The older partial PUT still works; the older flat maps are still returned.
- **A quote records the catalogue version it was priced with.** The server prices a quote with that version, so a quote made on a tablet that hadn't synced still matches the PDF it signs. An unknown version falls back to the current one.
- Optional `CATALOG_ADMIN_KEY` (header `X-Admin-Key`) locks saving; open by default. The proper fix is the Accounts module.

**Sales app**
- `CatalogRepository` keeps the last catalogue received (file on Android, browser storage on the web), uses it offline, and refreshes it when the home screen loads. Anything that doesn't parse is ignored, so the app is never left without prices.
- **A design is pinned to the catalogue it was opened with.** A price list published mid-meeting never moves the number the client is looking at; the next design uses it. The saved record carries `catalog_version`.
- The layout generator, the Edit tray, the appliance list, the benchtop list, the SST percentage and the 3D page's cabinet sizes all come from the catalogue. The BOQ shows the real installation count.

**Studio — Price list screen** (`frontend/src/components/PriceListEditor.tsx`, logic in `catalogEditor.ts`)
- Five parts: Modules (sizes, prices; add or remove a cabinet by width), Price by width (the rule, with worked examples), Finishes & benchtops, Installation & tax, Layout rules.
- Save makes a new version; any earlier one can be the starting point. A stale save is refused (with "load the newer list"); refused values are named by where they are; the office key is asked for only if the server has one; closing with unsaved changes asks first. The Studio prices with the saved version straight away.

**Verified**
- **Contract:** the same 11 cases give the same prices in the server, the Dart engine and the TypeScript engine; the expected numbers are worked out by hand, not by the engines.
- **Tests:** backend 41 (catalogue 39 + contract); Flutter 217; Studio 82 (38 for the editor logic); `tsc` clean; oxlint shows only the one older warning.
- **Studio in Chromium against a real server, 25 checks:** typing keeps focus, an empty box restores itself, add a module, examples follow the rule, save → version 2 with version 1 kept, the Studio total changes at once, a stale save is refused, a bad value is named, Escape with changes asks first, focus returns to the button, no horizontal scroll at 1440 and 1024 px. axe-core WCAG 2.2 A/AA: 0 violations in all five parts.
- **The whole chain in Chromium, 18 checks:** a price edited in the Studio is saved to the sales app's offline copy (without the old flat maps), shows in the Edit tray, and is what the app shows. A version published mid-meeting is *not* used for that design; the quote is priced by the server with the version the app showed, to the same total, and the PDF carries that total and "SST".
- **3D page:** `setCatalogModules` merges sizes (keeps the cooktop's "no hood" flag, ignores broken rows, survives junk input).

**Open, needs the client**
- The real catalogue and prices from SS Love's designer: every number in the sample is a stand-in, including SST at 8%, RM 120 installation and the RM 40 per 100 mm rule. This replaces the RM 300 fallback flagged in §16.
- Who may edit prices: the server's key is a stop-gap until the Accounts module (logins, roles).
- Not covered: appliance kinds beyond the six the 3D page draws; finishes can be renamed and re-priced but not added (their 3D look is in the app).

## 18. Session 2026-11-06 — pictures of the design, and a realistic render

**Why:** the apps showed a live 3D view but had no way to turn the design into a picture: nothing for the client to keep, nothing in the quote PDF. Asked for first: a "save picture" function, then a more realistic render.

**Quick pictures (the live look)**
- `assets/3d/index.html` `capturePictures(id)`: two pictures, front and angled (from the right, so an L-shape's return wall on the left is seen into), 1600×1000 JPEG. They use their own cameras, fitted to the walls and cabinets, so the viewer's view isn't moved, and leave out the editing aids (selection box, snap guide, the plan around the room). The page answers with a `pictures` event.
- **Sales app:** a camera icon on the 3D screen shows the pictures in a sheet (*Send on WhatsApp*, *Open to save*). Sending a quote takes them first and posts them as `design_images`. A quote waiting on the phone keeps them if they fit (about 1.5 MB); autosaved drafts never carry pictures (they are large and saved often).
- **Office server:** `design_images` are stored as files in `backend/design_pictures/` (gitignored). The first bytes decide JPEG or PNG, not the label; limits of 6 pictures and 6 MB each; a quote with bad pictures still works. They are printed in the PDF under "Your design" with a note that colours and finishes may differ, served at `/api/projects/<id>/picture/<n>`, and shown on `/pictures/<id>`, the page the client opens from the message (client name escaped). `POST /api/projects/<id>/pictures` takes pictures made before a quote exists. A quote sent again keeps its pictures unless new ones come.
- **Studio:** *Picture* in the header saves the 3D view as a 2000 px PNG in the view's shape, without the selection outline. Off in Plan and Elevation, whose dimension labels are page elements, not part of the canvas.
- **WhatsApp:** `wa.me` links can't carry an image, so the message carries a link; like the 3D link, it only opens on the office network. There is no save-to-gallery on Android (it needs a plugin, which would change `pubspec.lock`); *Open to save* opens the page in the browser instead.

**Realistic render**
- `renderPictures(id, {samples})`: the same two views, each the average of N frames (40 by default). Each frame is lit from a different part of the sky (a shadow-casting light moved over the hemisphere), with the sun nudged a little and the view moved by less than a pixel. The average gives soft shadows, darker corners and under the wall cabinets, smooth edges. No post-processing add-ons: plain three.js, so it works offline in the WebView and the browser.
- Progress and *Cancel*; while it runs the page refuses other captures and the app disables Quote and Picture. A cancelled or abandoned render puts the live view back exactly (size, lights, exposure, fog, camera). `--dart-define=RENDER_SAMPLES=n` changes the frame count (used to test).
- The quote uses the render only while the design is unchanged since it was made (a revision counter goes up with every change); otherwise it takes quick pictures.
- **What it is not:** not path tracing. No light bouncing between surfaces (colour bleeding), no photo textures (wood and stone are drawn in code), faint floor reflections. It looks like a clean architectural model render, clearly better than the live view, not a showroom photograph. Real finish photos from the designer would help most.
- **Speed:** measured only in headless Chromium with software rendering (no GPU): about 0.6 s per frame at 1600×1000, so about 25–50 s for both pictures at 40 frames. A tablet GPU should be several times faster; not measured on a device. If it is too slow, lower `_renderSamples`.
- Tuned by eye in `RENDER_LOOK` (sky strength, sun, ambient, exposure).

**Verified**
- **Tests:** Flutter 236, backend 86 (19 for pictures), Studio 87.
- **3D page in Chromium:** quick capture 12 checks (two JPEGs of 1600×1000, the app is told, the viewer's camera/size/selection untouched, both layouts, empty scene); render guard 7 checks (a quick capture during a render is refused, progress rises to 1, everything is put back exactly, Cancel works, quick capture works again).
- **Studio in Chromium:** 9 checks (PNG 2000 px wide, not blank, canvas restored, off in Plan, axe 0 violations).
- **Whole chain in Chromium:** 14 checks for quick pictures (sheet, Open to save → client page with two pictures, quote carries them, PDF has them) and 10 for the render (sheet, finishes, the quote reuses it without a new capture, server and PDF carry it).
- **Not tested:** a real tablet's speed and memory (the render holds about 26 MB of floats plus the pictures), WhatsApp with a real contact.

**Open**
- A render in the Studio (only quick pictures there).
- Real finish textures, and floor reflections, for a more photographic look.
- Android save-to-gallery / share sheet (a plugin).

## 19. Session 2026-11-06 — finish textures for the 3D view and the render

**Why:** the cabinets, worktops and floor were flat colours with a small grey pattern drawn in code, so even the realistic render looked like a model. Asked for: real finish textures.

**What it is and isn't.** The site that hosts free photographic textures (ambientCG, Poly Haven) isn't reachable from the build environment, and I did not want images of unclear licence in the repository. So the textures are **generated stand-ins** (`tool/gen_finish_textures.py`: original, procedural, deterministic), not photographs of SS Love's finishes. They read as oak, walnut, birch, quartz, Calacatta marble, black granite, slate, terrazzo and a plank floor. **The designer's real photographs replace them by dropping files in** (`assets/3d/textures/README.md` has the exact sizes and naming); no code changes.

**The pipeline** (`assets/3d/index.html`, `lib/features/viewer/scene/finish_textures.dart`)
- Each finish has a colour map and, where it has relief or uneven gloss, a normal map and a roughness map (physically based materials). Painted and matte-laminate fronts are a flat colour plus a faint micro texture. Worktops are physical materials with a clear coat (polished stone), floor planks tile every 2.4 m, grain runs down each door.
- The page loads from a string, so it can't fetch files. After it loads, the app sends the manifest and each image as a data URL (`registerFinishTextures`, `registerFinishFile`, `finishTexturesReady`), one JavaScript call per file, before the scene loads. About 3 MB of images (4 MB over the bridge); a test fails above 4 MB.
- **Fallback:** if they don't arrive (or the page runs without the app) it uses its old drawn textures, tinted as before. A picture or render asked for while textures are still decoding waits for them.
- **The benchtop choice now shows in 3D.** Calacatta quartz and Nero granite have their own look and matte laminate a flat colour; any other benchtop (the designer can add them) keeps the style's worktop (`BENCHTOP_LOOKS`).
- The texture set: 10 textures (3 woods, 6 stones, a floor), tile sizes in `manifest.json`, one size for all wood and one for all stone.

**Things found on the way**
- My noise "stretch" controls were inverted, which made the first woods look like contour maps and then like woven cloth (horizontal speckle crossing the vertical grain). Fixed in the generator; the woods now have long vertical grain, fine pores and gentle drift.
- The floor texture left its last 8 pixel rows black, which showed as dark lines every 2.4 m. Fixed (16 planks of 128 px).
- The texture list is checked against the page by a test (every `tex: '…'` in the page exists in the manifest).

**Verified**
- Flutter 245 tests (9 new: the set, the hand-over, the viewer sends textures before the scene and the benchtop to the page). Backend 86, Studio 87 unchanged.
- **3D page in Chromium, 18 checks:** fallback without textures, a picture asked for during decoding, every style's finishes, the benchtops, an unknown benchtop key, pictures.
- **Through the real app in Chromium, 11 checks:** every texture file reaches the page (about 6.5 s from tapping "View in 3D" with software rendering), the fronts and floor are textured, choosing Calacatta and granite in the Edit panel changes the worktop, Industrial puts walnut on and Minimalist paints, a render comes back with the finishes on.
- The earlier picture (12) and render (7) checks still pass.

**Not done / open**
- **Real photographs** of SS Love's finishes: the main thing that would make it look photographic.
- **Studio:** its own 3D view still uses the old drawn finishes; the texture pipeline is only in the sales app's 3D page (and so in its pictures and render).
- The renders still have no light bouncing or real reflections, so a photograph-level look also needs those.
- Painted white is a flat colour; a real lacquer sample would need a photo only if it has texture.

## 20. Session 2026-11-06 — dressing the scene (doors, backsplash, decor, light)

**Why:** reference pictures of finished kitchens (a grey shaker kitchen, a warm kitchen with an island and open shelves, a navy raised-panel kitchen) showed two kinds of difference from our render: what is *in* the scene, and the lighting engine (light bouncing, true reflections). Asked which to do first, the answer was the scene; the lighting engine is still the open half.

**Built** (`assets/3d/index.html`, `lib/features/viewer/models/scene_look.dart`)
- **Door styles:** flat, shaker (frame round a recessed panel, with a fine lip) and raised panel (two steps up from the recess); framed wall units get a cornice. `setDoorStyle` rebuilds the cabinets.
- **Tile backsplash:** subway and hexagon, between the worktop and the wall units, following the base units (so it grows and shrinks with them), along the side wall of an L, and stopping at a window. Tile textures come from the generator (a tile sheet, relief and gloss maps).
- **Decor:** plates, a fruit bowl, jars, a plant, a chopping board, a utensil crock, a kettle and a knife block, from simple shapes, placed on worktops by a fixed rule (the same design always gets the same decor; some worktop stays bare). Not cabinets: nothing selects them, nothing prices them.
- **Light:** `day`, or `evening` (warm sky, the main light dimmed, strong warm under-cabinet lights). Day also gets a gentle under-cabinet light: without it the backsplash sat in the cabinets' shadow as a dark slab. A render re-balances for the evening too.
- **App:** a palette button opens a "Look" sheet (doors, backsplash, light, decor). The choice is saved with the design (`scene` in the record), sent with the quote, and put on the page before the cabinets arrive.
- **Honesty about what the quote covers:** the server keeps only the known parts of the look, and prints under the pictures in the PDF and on the client's page that the decor and the backsplash tile shown are not part of the quote and that the door style shown is for illustration.

**Open decisions**
- **Pricing:** door style and backsplash don't change the price (there is no price rule for them). If shaker or raised doors cost more at SS Love, the catalogue needs a rule; until then the note above is what keeps a client from assuming otherwise.
- The sample look is not SS Love's. Their real door profiles and tile choices need the designer.

**Still missing for the reference pictures**
- **Lighting engine:** no light bouncing between surfaces, no true reflections in the floor, steel or stone, no glass.
- **Room context:** no ceiling with downlights, no other walls, rugs or furniture; an island, open shelves and glass-front doors are not in the layout generator.
- **Better models:** props and appliances are simple shapes (the reference pictures use detailed models); a stainless fridge with its door lines, a real oven, gas hob grates.

**Verified:** Flutter 256 tests, backend 97 (11 new for the look and the quote note), Studio 87. 3D page in Chromium: scene check 21 (door styles, backsplash and the window, decor, light, L-shape, pictures with everything on), textures 18, pictures 12, render guard 7. Through the real app in Chromium: the Look sheet changes the page, the server keeps the look, and the PDF and the picture page carry the note.
