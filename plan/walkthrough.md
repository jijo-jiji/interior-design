# Complete System Walkthrough — Mobile Sales Closer & Studio Web Workbench

## Architecture Overview

The system is now a complete **Dual-Platform Architecture** delivering on the vision of high-speed consultative interior design sales:
1. **Mobile / Tablet App (The Sales Closer)**: Touch-first, offline-capable, magnetic snapping, 1-tap style switches, dynamic budget odometer, and on-screen signature pad for 15-minute closing in front of clients.
2. **Web Studio Workbench (The Studio & Factory Hub)**: Desktop CAD environment served directly at `http://localhost:8000/studio` for estimators, senior designers, and factory CNC production.

```
┌─────────────────────────────────────────────────────────────┐
│             MOBILE / TABLET IN-PERSON CLOSER                │
│              (Flutter + Local Three.js Engine)              │
├──────────────────────────────┬──────────────────────────────┤
│ • Consultation Intake Hub    │ • Magnetic Cabinet Snapping  │
│ • Camera Wall Tracing        │ • 1-Tap Style Archetypes     │
│ • 2D Blueprint Calibration   │ • Live Dynamic Odometer (CPQ)│
│ • 10s Template Room Dial     │ • Digital Signature Modal    │
└──────────────────────────────┴──────────────┬───────────────┘
                                              │ POST /quote
                                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    UNIFIED CLOUD CORE                       │
│                     (Python FastAPI)                        │
├─────────────────────────────────────────────────────────────┤
│ • Persistent JSON Database (`projects_db.json`)             │
│ • Dynamic Pricing & Material Tier Multipliers               │
│ • Signed Agreement PDF Generator (ReportLab)                │
│ • AutoCAD R12 ASCII DXF CAD Exporter                        │
└─────────────────────────────────────────────┬───────────────┘
                                              │ Real-Time Sync
                                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  DESKTOP WEB WORKBENCH                      │
│            (Served at http://localhost:8000/studio)         │
├──────────────────────────────┬──────────────────────────────┤
│ • Pipeline CRM (Live Quotes) │ • Placed Cabinet Schedule    │
│ • Multi-Camera 3D CAD Views  │ • Signed PDF Download        │
│ • Top-Down & Elevation Views │ • CNC DXF Factory Handover   │
│ • Master Catalog Price Matrix│ • Zero-Config Desktop Access │
└──────────────────────────────┴──────────────────────────────┘
```

---

## What Was Built in Option C (Dual Web Companion)

### 1. Studio Web Workbench Interface ([`index.html`](file:///c:/Users/User/Documents/3dmodel/backend/static/studio/index.html))
- Hosted directly by FastAPI at `http://localhost:8000/studio` (no separate Node/Vite server needed).
- **Three-Panel Modern CAD Layout**:
  - **Left Panel (Consultation Pipeline & CRM)**:
    - Real-time list of all mobile consultations with search and filter.
    - Displays client name, quote ID, total in AUD, and slot deposit badges ("Priority Locked (\$250)", "Estimate").
    - Clicking any card immediately loads the 3D space and financial schedule.
  - **Center Viewport (3D Studio Engine)**:
    - Three.js WebGL viewport with studio lighting and shadow map.
    - **Multi-Camera Controls**:
      - `3D Orbit`: Full perspective rotation.
      - `Top (Plan View)`: Orthographic top-down architectural layout.
      - `Front Elevation`: Direct front view with cabinet millimeter height alignments.
  - **Right Panel (Engineering & Factory Handover)**:
    - Client contact inspector (phone, WhatsApp, email, consultant ID).
    - Placed cabinet schedule table ($W \times H \times D\text{ mm}$ CNC specs).
    - Itemized BOQ financial summary (materials subtotal, GST, total project price).
    - **One-Click Export Actions**:
      - 📄 **Download Signed PDF Agreement**: Opens the ReportLab PDF complete with the customer's actual finger signature.
      - 📐 **Export AutoCAD DXF for Factory CNC**: Instant download of standard `.dxf` CAD file.
  - **Master Catalog Modal**:
    - Manage base prices for all cabinet models.
    - Adjust style multipliers (Japandi, Minimalist, Nordic, Industrial).
    - Update installation labour rates per cabinet.

### 2. Factory AutoCAD DXF Exporter ([`dxf_exporter.py`](file:///c:/Users/User/Documents/3dmodel/backend/dxf_exporter.py))
- Generates standard **AutoCAD Release 12 ASCII DXF files** (`AC1009`).
- Exports layered architectural entities in millimeters:
  - `WALLS`: Wall perimeter boundary in both Elevation and Plan views.
  - `OBSTACLES`: Door and window cutouts with dimension labels.
  - `CABINETS_BASE`, `CABINETS_WALL`, `CABINETS_TALL`: Cabinet bounding boxes and labels.
  - `DIMENSIONS`: Annotation text.
- Compatible with AutoCAD, SolidWorks, Rhino, and factory CNC nesting software.

### 3. Persistent Project Database & REST Endpoints ([`main.py`](file:///c:/Users/User/Documents/3dmodel/backend/main.py))
- `GET /api/projects`: Lists all client consultations.
- `GET /api/projects/{id}`: Full project JSON.
- `PUT /api/projects/{id}`: Save studio revisions.
- `GET /api/catalog` & `PUT /api/catalog`: Master price matrix management.
- `GET /api/export/{id}/dxf`: Streams generated DXF file.
- `GET /pdf/{id}`: Serves stamped PDF agreement.
- `GET /studio`: Serves the desktop Studio Workbench.

---

## Verification & Test Results

### 1. Backend Studio Tests (`python backend/test_studio.py`)
```
[PASS] test_list_projects: returned 2 projects
[PASS] test_get_single_project: loaded project successfully
[PASS] test_catalog_endpoints: catalog get & update verified
[PASS] test_dxf_export: valid AutoCAD R12 DXF generated (length: 4489 bytes)

ALL STUDIO BACKEND TESTS PASSED!
```

### 2. Mobile Flutter Unit Tests (`flutter test`)
```
00:00 +0: CPQEngine Tests Empty room returns zero total
00:00 +1: CPQEngine Tests Single base_800 and wall_600 in Japandi (1.0x baseline)
00:00 +2: CPQEngine Tests Industrial style applies 1.18x material multiplier
00:00 +3: CPQEngine Tests Obstacle allowances reduce subtotal appropriately
00:00 +4: Floor Plan 2-Point Calibration Math Tests Calculates Euclidean pixel distance
00:00 +5: Floor Plan 2-Point Calibration Math Tests Computes scale ratio accurately
00:01 +6: PayloadBuilder — JSON structure wall block contains correct keys
00:01 +7: PayloadBuilder — JSON structure obstacle width converts correctly
00:01 +8: PayloadBuilder — JSON structure distance_from_left
00:01 +9: PayloadBuilder — JSON structure toJson produces valid parseable JSON
00:01 +10: PayloadBuilder — JSON structure salesperson_id is hardcoded
00:02 +11: ScaleMath — pixel↔mm round-trip computeRatio
00:02 +12: ScaleMath — pixel↔mm round-trip mmToPx
00:02 +13: ScaleMath — pixel↔mm round-trip pxToMm
00:02 +14: ScaleMath — pixel↔mm round-trip round-trip is lossless
00:02 +15: ScaleMath — pixel↔mm round-trip clampLeft
00:02 +16: ScaleMath — pixel↔mm round-trip clampTop
00:02 +17: ScaleMath — pixel↔mm round-trip snapToGrid
00:02 +18: App smoke test — camera screen renders
00:03 +19: All tests passed!
```

---

### 3. Automated Clickable Feature Verification & MP4 Recording
- **Execution Script**: [`backend/record_studio_test.py`](file:///c:/Users/User/Documents/3dmodel/backend/record_studio_test.py)
- **Deliberate Pacing**: 1.5s to 2.5s per action, giving smooth, clear human review without jerky transitions.
- **Recording Specs**:
  - **Format**: MP4 (`h264`, `yuv420p`, `+faststart` web-optimized)
  - **Resolution**: $1600 \times 950$ px
  - **Framerate**: 25.0 fps
  - **Duration**: 45.8 seconds
  - **File Size**: 1.46 MB
  - **Output Paths**:
    - Project Artifact: [`plan/studio_workbench_test_sequence.mp4`](file:///c:/Users/User/Documents/3dmodel/plan/studio_workbench_test_sequence.mp4)
    - Brain Artifact: [`studio_workbench_test_sequence.mp4`](file:///C:/Users/User/.gemini/antigravity/brain/3479f5a9-6103-4821-b60a-cb5ccf5febc6/studio_workbench_test_sequence.mp4)

#### Timestamped Action Breakdown in the Recording:
| Timestamp | Action Tested | Visual Response / Verification |
|:---:|:---|:---|
| **00:00 - 00:04** | Initial Studio Boot & Pipeline Sync | Studio Workbench loads with 3-panel CAD layout. Projects list fetched from backend; Emma Watson consultation initially loaded. |
| **00:04 - 00:08** | Step 1: Hover & Click Project 1 | Hovers and clicks `Emma Watson (Industrial Luxe)`. 3D scene renders dark charcoal matte cabinets with black metal accents; BOQ updates to \$3,656 AUD. |
| **00:08 - 00:13** | Step 2: Hover & Click Project 2 | Switches to `Marcus Aurelius (Japandi)`. 3D scene smoothly updates to warm natural oak cabinets and beige textured wall; BOQ reflects \$2,556 AUD with Priority Locked badge. |
| **00:13 - 00:18** | Step 3a: Top-Down Plan View Button | Clicks `#btn-cam-top`. Camera transitions to top-down 2D architectural blueprint angle showing wall depth and cabinet footprint alignments. |
| **00:18 - 00:23** | Step 3b: Front Elevation View Button | Clicks `#btn-cam-front`. Camera shifts to direct front orthographic view displaying floor clearances and counter heights. |
| **00:23 - 00:27** | Step 3c: 3D Orbit View Button | Clicks `#btn-cam-persp`. Returns camera to natural 3D isometric perspective. |
| **00:27 - 00:31** | Step 4: 3D Mouse Drag Orbiting | Mouse drags across the 3D canvas, smoothly orbiting around the room to inspect side cabinet depths and lighting reflections. |
| **00:31 - 00:38** | Step 5: Master Catalog & Pricing Modal | Opens "Master Catalog & Pricing Matrix" modal, updates `Base 800mm` pricing to \$440, clicks "Save Pricing Matrix", and handles confirmation dialog. |
| **00:38 - 00:43** | Step 6: AutoCAD DXF Factory Export | Re-selects Project 1 and clicks "Export AutoCAD DXF for Factory CNC". Browser completes instant download of `QT-816BB0DC.dxf`. |
| **00:43 - 00:45** | Step 7: Signed PDF Agreement Inspection | Hovers "Download Signed PDF Agreement" button (linking to ReportLab digital signature PDF) and concludes sequence. |

---

## How to Run the Complete System

### Run the Backend & Web Studio:
```powershell
cd c:\Users\User\Documents\3dmodel\backend
python main.py
```
- **Web Studio Workbench**: Open `http://localhost:8000/studio` in any desktop browser (Chrome, Edge, Safari).
- **API Documentation**: Accessible at `http://localhost:8000/docs`.

### Run the Mobile Sales Closer:
```powershell
cd c:\Users\User\Documents\3dmodel
flutter run
```

### Re-Run Automated Playwright Screen Recording:
```powershell
python backend/record_studio_test.py
```

