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
