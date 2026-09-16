# High-Speed In-Person Interior Design Sales Accelerator: Coohom Benchmark & Dual-Platform Architecture

## Executive Summary

Interior design sales cycles traditionally suffer from high drop-off rates (**40% to 65% of qualified leads fail to close after the initial consultation**). The primary culprit is the **"Consultation-to-Quotation Gap"**:
1. A salesperson or designer visits a site or meets a client at a showroom.
2. They take manual tape measurements or snap photos.
3. They take 3 to 7 days back at the office to draft the 2D CAD, assemble a 3D model, and generate a Bill of Quantities (BOQ).
4. By the time the follow-up meeting occurs, client urgency has evaporated, competing firms have pitched, or budget anxiety has set in.

**Our Core Objective:** Transform this into a **"Single-Session In-Person Closing Machine"** that operates live on an Android/iOS tablet or laptop, allowing a sales consultant to go from **Room Capture → Live Parametric Customization → Instant Real-Time Budgeting → Digital Deposit in under 15 minutes**.

---

## 1. Deep Benchmark: Coohom Dissection & The Sales Bottleneck

### What Coohom Does Exceptionally Well
[Coohom](https://www.coohom.com/) is an industry standard for cloud-based interior design visualization. Its core technical and product strengths are:
- **Massive Cloud Asset Ecosystem:** Over 1,000,000+ render-ready 3D models (furniture, lighting, cabinetry, textures).
- **ExaCloud™ Distributed Ray-Tracing:** Delivers 4K/16K photorealistic still renders and 720° VR panoramas in seconds to minutes.
- **Parametric Cabinetry & Joinery (Kitchen & Bath):** High customizability of carcass panels, door fronts, plinths, and countertop edge profiles.
- **BIM/CAD Construction Drawing Export:** Direct generation of floor plans, elevations, section views, and cutting lists.

### Why Coohom is Too Slow for Sales Reps in Front of Clients
Despite its power, Coohom fails in face-to-face sales closing due to five structural bottlenecks:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      THE COOHOM IN-PERSON PARADOX                       │
├──────────────────────────────────┬──────────────────────────────────────┤
│ Desktop Designer Reality         │ In-Person Sales Reality              │
├──────────────────────────────────┼──────────────────────────────────────┤
│ Designed for mouse + dual monitors│ Used on a tablet/touchscreen on a couch│
│ 1,000,000 items (choice overload)│ 3-5 curated style packages needed    │
│ Precision 3D transformation gizmo│ Magnetic auto-snapping needed        │
│ Disconnected quoting / ERP export│ Live dynamic price ticker required   │
│ 3-5 minute cloud render wait     │ 60 FPS real-time local WebGL needed  │
└──────────────────────────────────┴──────────────────────────────────────┘
```

1. **Choice Paralysis & UI Clutter:** When a salesperson opens a library of 20,000 sofas or 5,000 laminate textures in front of a client, it destroys sales momentum. Clients enter decision fatigue.
2. **Desktop-First Micro-Interactions:** Coohom's mobile app is largely a **read-only viewer** for panoramic tours. Trying to snap walls, reposition wall cabinets, or adjust dimensions on a touchscreen results in missed taps, awkward panning, and software fumbling that erodes client trust.
3. **No Native Live CPQ (Configure, Price, Quote):** In Coohom, pricing is detached from live drafting. A sales rep cannot say: *"If we switch these base cabinets from matte laminate to fluted oak and add a quartz waterfall edge, your exact price changes by +$420."*
4. **Cloud Latency & Network Vulnerability:** In on-site residential visits, Wi-Fi or 5G can be unstable. If a tool relies on continuous cloud round-trips for scene manipulation, the sales presentation freezes.

---

## 2. Interior Design UX Deep Dive: Bridging the Software Engineer's Blind Spots

As a software engineer, building for interior design sales requires understanding **spatial psychology, consultative sales mechanics, and ergonomic design rules**.

### Blind Spot 1: The "Blank Canvas" Mistake vs. Curated Archetypes
*   **The Engineer's Instinct:** Give the user a blank 3D grid and full freedom to place any object anywhere.
*   **The Interior Sales Reality:** Blank canvases cause panic. Sales reps never sell individual cabinets; they sell **aspirational lifestyle packages**.
*   **UX Solution ("Style Archetypes"):**
    *   Provide 3 to 4 one-tap design recipes: **"Japandi Warmth"**, **"Modern Minimalist"**, **"Industrial Luxe"**, **"Nordic Organic"**.
    *   Tapping an archetype instantly populates the captured room with coordinated materials: matched wall paint, baseboard profiles, flooring texture, cabinetry front style, handle hardware, and countertop stone.
    *   The client selects an archetype, then customizes only high-impact focal points (e.g., cabinet color, appliance finish, countertop thickness).

### Blind Spot 2: Free 3D Gizmos vs. Magnetic Constraint Snapping
*   **The Engineer's Instinct:** Provide standard 3D translation/rotation handles (X, Y, Z gizmos).
*   **The Interior Sales Reality:** Trying to manipulate a 3D gizmo on a tablet in front of a client leads to floating cabinets, intersecting walls, or cabinets facing backwards.
*   **UX Solution ("Magnetic Smart Rails"):**
    *   **Wall Attachment:** When a cabinet is selected, it only slides along the 2D plane of the host wall.
    *   **Neighbor Auto-Snap:** When dragged within 100mm of an existing cabinet, it magnetically snaps flush to the adjacent unit.
    *   **Auto-Height Leveling:** Base cabinets automatically snap to floor level (Y=0, height 850-900mm). Wall cabinets automatically snap to header height (e.g., Y=1500mm).

### Blind Spot 3: Spatial Clearance & Ergonomic Safety Rules
*   **The Interior Rulebook:**
    *   **Walkway Clearance:** Minimum 900mm (ideal 1100mm-1200mm) between facing cabinets or kitchen islands.
    *   **Door & Window Collision:** Cabinets cannot overlap window frames or block door swing radii.
    *   **The Working Triangle:** Sink, cooktop, and refrigerator distance must balance ergonomic reach (sum between 4m and 8m).
*   **UX Solution ("Ghost Clearances & Soft Clashing"):**
    *   Display semi-transparent green/red clearance zones on the floor when dragging appliances or island units.
    *   Prevent invalid placements automatically (e.g., base unit stops sliding when it reaches the edge of a door casing).

### Blind Spot 4: Price Transparency & The "Live Budget Odometer"
*   **The Sales Psychology:** Clients want to customize, but dread the surprise total at the end.
*   **UX Solution ("Dynamic Odometer"):**
    *   A persistent bottom bar showing:
        $$\text{Current Estimate: } \$12,450 \quad \vert \quad \text{Financing: } \$289/\text{mo} \quad \vert \quad \text{Today's Lock-in Deposit: } \$300$$
    *   When swapping a finish or adding a tall pantry unit, the price odometer rolls up or down with micro-animations. This shifts the conversation from *"Can I afford this?"* to *"Do I prefer the luxury laminate for only \$18 more per month?"*

### Blind Spot 5: The "Closing Bridge" (Signature & Deposit Gateway)
*   The software must not end with *"Exporting 3D render"*. It ends with **Deal Commitment**:
    1. **One-Tap BOQ Generation:** Itemized breakdown of modular units, materials, hardware, and labor.
    2. **Sign On Screen:** Customer signs with their finger on the tablet.
    3. **Deposit QR Code / Stripe Terminal:** Instant 5%-10% booking deposit.
    4. **Automated WhatsApp / Email Handover:** Instant interactive 3D web link and PDF proposal sent to client's phone before the rep leaves the room.

---

## 3. Multi-Modal Room Input Pipeline

To make the app fast in any client setting, the system must support **three input modalities**, progressing from fastest to most detailed:

```
                          ┌───────────────────────────┐
                          │   ROOM INPUT MODALITIES   │
                          └─────────────┬─────────────┘
                                        │
         ┌──────────────────────────────┼──────────────────────────────┐
         ▼                              ▼                              ▼
┌──────────────────┐          ┌──────────────────┐           ┌──────────────────┐
│  Mode 1: Camera  │          │  Mode 2: 2D Plan │           │  Mode 3: Quick   │
│  Wall/Room Trace │          │  (PDF / CAD / Img)│          │  Template Shape  │
├──────────────────┤          ├──────────────────┤           ├──────────────────┤
│ • ARCore / ARKit │          │ • OpenCV / AI    │           │ • Rect / L-Shape │
│ • Static photo   │          │   segmentation   │           │ • Dimension dial │
│   trace (current)│          │ • CAD/DXF import │           │ • 10-second setup│
│ • Android Depth  │          │ • Auto wall extr.│           │   fallback       │
└──────────────────┘          └──────────────────┘           └──────────────────┘
```

### Modality 1: Android Camera Wall Tracing & AR Room Capture
1. **The Static Trace Approach (Built in `c:\Users\User\Documents\3dmodel\`):**
   - **Why it's smart:** Eliminates AR drift. Snapping a photo freezes perspective. Rep drags obstacle boxes (doors, windows, outlets) over the frozen frame with scale calibration.
   - **Enhancement:** Use Android `ARCore Depth API` / `Raw Depth` to auto-detect the ground plane and wall boundary, suggesting the initial wall polygon without manual mm typing.
2. **Multi-Wall Panoramic Sweep:**
   - Allow user to pivot across 2 or 3 connected walls. By tracking camera rotation angles via device IMU (gyroscope), the app connects adjacent wall segments into an L-shape or U-shape automatically.

### Modality 2: 2D Floor Plan Processing (PDF, Photo, CAD)
Clients often already have a floor plan from their building developer, architect, or real estate agent.
1. **Input Types:**
   - Vector PDF / DWG / DXF (high precision, 95%+ auto-parseable).
   - Raster Images (JPG/PNG scan, smartphone snapshot of blueprint).
2. **Computer Vision & AI Conversion Pipeline:**
   - **Step 1: Rectification & Preprocessing:** Perspective transform (homography) to flatten phone photos of paper floor plans; adaptive thresholding.
   - **Step 2: Scale Calibration:** Rep taps two corners of a known dimension (e.g., standard door width 900mm or a dimension line labeled "4000").
   - **Step 3: Wall & Opening Detection:**
     - Using deep learning models (e.g., RoomFormer, Floor-SP, or YOLO-based architectural feature detection) to detect wall lines, windows, and swing doors.
     - Fallback / Hybrid: User taps wall endpoints; line-segment snap snaps rough user clicks to high-contrast wall lines.
   - **Step 4: Vector to 3D Extrusion:**
     - Generate closed 2D polygon loops.
     - Extrude 2D floorplan into 3D walls in Three.js (`THREE.ExtrudeGeometry`), automatically cutting out window and door portals using boolean subtraction or `THREE.Shape.holes`.

### Modality 3: 10-Second Template Dial (The Instant Fallback)
- If the room is cluttered, the floor plan is missing, or the camera is inconvenient:
- Rep selects **Single Wall**, **L-Shape**, **Galley (Parallel Walls)**, or **U-Shape**.
- Two sliders: *Width (mm)* and *Ceiling Height (mm)*.
- Ready for cabinet placement in 10 seconds flat.

---

## 4. Dual-Platform Architecture: Mobile/Tablet vs. Web

To balance **in-person closing speed** with **back-office depth**, the system must be split into two purpose-built interfaces sharing a unified cloud data layer:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             UNIFIED CLOUD CORE                              │
│              (FastAPI + PostgreSQL + Supabase / WebSocket Sync)             │
│                                                                             │
│  • Scene JSON Payload        • Modular Catalog Engine   • Real-Time Pricing │
│  • PDF Proposal Generator    • CRM / Lead Management   • Cloud Render Queue│
└───────────────────────▲─────────────────────────────▲───────────────────────┘
                        │                             │
                        │ Real-time Sync              │ Real-time Sync
                        │                             │
┌───────────────────────▼─────────────┐   ┌───────────▼───────────────────────┐
│     TABLET / MOBILE SALES APP       │   │        STUDIO WEB WORKBENCH       │
│    (Flutter + Three.js WebView)     │   │      (React / Three.js / WebGPU)  │
├─────────────────────────────────────┤   ├───────────────────────────────────┤
│ • On-site measurement & scanning    │   │ • Full catalog & pricing rule mgmt│
│ • 1-tap style archetype switches    │   │ • Complex millwork custom joinery │
│ • Magnetic cabinet snap-and-slide   │   │ • Multi-room whole-house projects │
│ • Live Dynamic Budget Odometer      │   │ • CNC manufacturing export (DXF)  │
│ • In-person digital signature       │   │ • 4K/8K photorealistic cloud render│
│ • Instant booking deposit gateway   │   │ • Team pipeline & lead assignment │
│ • Runs 100% offline if needed       │   │ • Desktop mouse & dual-monitor UX │
└─────────────────────────────────────┘   └───────────────────────────────────┘
```

### Tablet / Mobile (The In-Person Weapon)
- **Primary User:** Sales Consultant / Field Representative.
- **Environment:** In the client's home, on-site, showroom floor, coffee shop.
- **Tech Stack:** **Flutter (for high-speed native UI & camera) + Local Three.js (via WebView or WebGL)**.
- **Key UX Tenet:** Everything must be operable with **thumbs/fingers**, zero precision dialogs, zero waiting for server rendering. Runs completely offline if the network drops.

### Web Workbench (The Back-Office Engine)
- **Primary User:** Senior Interior Designer, Estimator, Manufacturing Engineer, Admin.
- **Environment:** Office workstation with dual monitors, mouse, keyboard.
- **Tech Stack:** **React / Next.js + Three.js / React Three Fiber + TailwindCSS**.
- **Key Features:**
  - Catalog upload: importing supplier GLB models, configuring dimensional constraints (min/max parametric rules).
  - Price matrix management: margin multipliers, labor rates, regional tax rules.
  - Deep BIM/CNC detailing: exporting `.dxf` / cutting lists for cabinet factories.
  - Reviewing leads closed by the sales reps on the road.

---

## 5. End-to-End In-Person Sales Workflow (The 15-Minute Close)

```
[Minute 0-3: Capture]
Camera Wall Trace OR 2D Floor Plan Scan OR Shape Preset
         │
         ▼
[Minute 3-5: Co-Design & Style]
Select Style Archetype (e.g. Japandi Oak) → Room instantly skins
         │
         ▼
[Minute 5-10: Modular Layout]
Drag 4-6 base & wall cabinets → Magnetic snap along walls
Swap focal finishes (Countertop, Cabinet door style)
         │
         ▼
[Minute 10-12: Price Validation]
Dynamic Odometer recalculates live ($12,850 total / $310 mo)
Rep presents "Good / Better / Best" options side-by-side
         │
         ▼
[Minute 12-15: The Close]
Generate 1-page PDF proposal → Client signs on screen
Collect $300 production slot deposit → Automated 3D link sent to WhatsApp
```

---

## 6. Options Comparison

- **Option A (The In-Person Touch Closing UX):** Magnetic cabinet snapping, 1-tap style switches, dynamic budget odometer, and on-screen signature.
- **Option B (2D Floor Plan & Multi-Modal Ingestion):** Build the floor plan upload, scale calibration, and automatic 3D extrusion engine for blueprints and sketches.
- **Option C (Dual Web Companion):** Scaffold the Web-based studio interface syncing with the mobile app.
