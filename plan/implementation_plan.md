# Static Trace Canvas — Full System Architecture

## Overview

A Flutter mobile app that lets a salesperson:
1. **Snap** a photo of a client's wall
2. **Trace** windows/doors over the frozen photo using draggable boxes (pixel-to-mm math)
3. **Generate** a local 3D wall instantly via Three.js inside a Flutter WebView — no server round-trip
4. **Drag-and-drop** virtual cabinets into the 3D scene
5. **Send** the final layout to a Python backend for pricing, PDF quote, and CRM logging

---

## Open Questions

> [!IMPORTANT]
> **Q1 — Platform target**: iOS only, Android only, or both?
> Affects camera plugin setup, WebView sandboxing, and asset bundling strategy.

> [!IMPORTANT]
> **Q2 — Cabinet GLB assets**: Do you already have `.glb` cabinet models, or should I use simple Three.js primitive geometry (box meshes) as placeholders for now?

> [!IMPORTANT]
> **Q3 — Python backend**: Do you have an existing Django/FastAPI endpoint, or should I scaffold the backend service too? The blueprint says Python handles pricing + PDF + CRM.

> [!IMPORTANT]
> **Q4 — Authentication**: Does the salesperson need to log in? (Affects state management scope.)

> [!NOTE]
> I will scaffold the complete Flutter project now with placeholder answers, and you can fill in the gaps as we iterate.

---

## Proposed Changes

### Layer 0 — Flutter Project Bootstrap

#### [NEW] `pubspec.yaml`
- Dependencies: `camera`, `path_provider`, `riverpod` (flutter_riverpod), `webview_flutter`, `image_picker`, `permission_handler`, `uuid`

#### [NEW] `android/` + `ios/` — Camera & WebView permissions

---

### Layer 1 — Base Canvas (`LayoutBuilder` + `Stack`)

#### [NEW] `lib/features/trace/widgets/trace_canvas.dart`
- `LayoutBuilder` wraps the full tracing area
- Exposes `constraints.maxWidth / constraints.maxHeight` to the state notifier
- Root child is a `Stack` — absolute coordinate system for all layers

---

### Layer 2 — Frozen Environment

#### [NEW] `lib/features/trace/screens/camera_screen.dart`
- Shows live `CameraPreview`
- On capture: disposes `CameraController`, writes file via `takePicture()`
- Navigates to `TraceScreen`, passing the `XFile` path

#### [NEW] `lib/features/trace/screens/trace_screen.dart`
- Bottom layer of `Stack`: `Image.file(File(imagePath))` — the frozen photo
- `fit: BoxFit.cover` inside `LayoutBuilder` bounds

---

### Layer 3 — Obstacle Dragger

#### [NEW] `lib/features/trace/widgets/trace_box.dart`
- Stateful widget: `TraceBox(id, label, color)`
- `Positioned(left, top, width, height)` wrapping a semi-transparent `Container`
- `GestureDetector.onPanUpdate`: `left += delta.dx`, `top += delta.dy`, `setState()`
- Corner handle for resizing (drag bottom-right corner)
- Label badge showing real-world mm dimensions

#### [NEW] `lib/features/trace/models/obstacle.dart`
```dart
class Obstacle {
  final String id;
  final ObstacleType type; // window | door
  double leftPx, topPx, widthPx, heightPx;
}
```

---

### Layer 4 — Scale Ratio & Pixel-to-MM Math

#### [NEW] `lib/features/trace/screens/wall_setup_screen.dart`
- Input: real wall width (mm), real wall height (mm), wall depth (mm)
- Calculates: `scaleRatio = screenWidthPx / wallWidthMm`
- Stored in Riverpod `WallSetupNotifier`

#### [NEW] `lib/features/trace/providers/wall_provider.dart`
```dart
// Riverpod providers
final wallSetupProvider = StateNotifierProvider<WallSetupNotifier, WallSetup>(...);
final obstaclesProvider = StateNotifierProvider<ObstaclesNotifier, List<Obstacle>>(...);
```

#### [NEW] `lib/features/trace/utils/scale_math.dart`
```dart
double pxToMm(double px, double ratio) => px / ratio;
double mmToPx(double mm, double ratio) => mm * ratio;
Offset positionToMm(Offset px, double ratio) => ...
```

---

### Layer 5 — JSON Payload Builder

#### [NEW] `lib/features/trace/utils/payload_builder.dart`
- Converts `List<Obstacle>` + `WallSetup` → the lean JSON:
```json
{
  "wall": { "width_mm": 4000, "height_mm": 3000, "depth_mm": 150 },
  "obstacles": [{ "type": "window", "distance_from_left_mm": 1200, ... }]
}
```

---

### Layer 6 — Local 3D Renderer (Three.js in WebView)

#### [NEW] `assets/3d/index.html`
- Self-contained Three.js (r165, loaded from CDN or bundled)
- JavaScript API: `window.loadScene(jsonString)` — called from Flutter
- Renders: parametric wall (ExtrudeGeometry) + hole cuts (Shape.holes) + OrbitControls
- Cabinet drag: tap sidebar icon → spawns BoxGeometry or loads `.glb` via GLTFLoader
- Flutter ↔ JS bridge via `WebViewController.runJavaScript()` and `JavascriptChannel`

#### [NEW] `lib/features/viewer/screens/viewer_screen.dart`
- `WebViewWidget` loading `assets/3d/index.html`
- On `WebViewController.onPageFinished`: calls `loadScene(jsonPayload)`
- Floating sidebar with cabinet type buttons
- "Finalize" button → collects placed cabinet list → sends to Python API

---

### Layer 7 — Python Backend (Business Logic)

#### [NEW] `backend/main.py` (FastAPI)
- `POST /quote` — receives final layout JSON, calculates pricing, generates PDF
- `POST /lead` — logs client info to DB
- Uses `reportlab` for PDF generation

#### [NEW] `backend/requirements.txt`
- fastapi, uvicorn, reportlab, sqlalchemy, python-multipart

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter App (Device — fully offline capable)               │
│                                                             │
│  CameraScreen → TraceScreen → ViewerScreen                  │
│       │               │              │                      │
│  takePicture()   Riverpod State   WebView                   │
│  Image.file()    + Scale Math     Three.js                  │
│                  + JSON Build     Local 3D                  │
└─────────────────────────────────┬───────────────────────────┘
                                  │ POST /quote (on Finalize)
                          ┌───────▼──────────┐
                          │  Python FastAPI   │
                          │  Pricing Engine   │
                          │  PDF Generator    │
                          │  CRM/DB Logger    │
                          └──────────────────┘
```

## File Map

```
3dmodel/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── features/
│   │   ├── trace/
│   │   │   ├── models/obstacle.dart
│   │   │   ├── providers/wall_provider.dart
│   │   │   ├── screens/
│   │   │   │   ├── camera_screen.dart
│   │   │   │   ├── wall_setup_screen.dart
│   │   │   │   └── trace_screen.dart
│   │   │   ├── widgets/
│   │   │   │   ├── trace_canvas.dart
│   │   │   │   └── trace_box.dart
│   │   │   └── utils/
│   │   │       ├── scale_math.dart
│   │   │       └── payload_builder.dart
│   │   └── viewer/
│   │       └── screens/viewer_screen.dart
│   └── shared/
│       └── theme.dart
├── assets/
│   └── 3d/
│       └── index.html
└── backend/
    ├── main.py
    └── requirements.txt
```

## Verification Plan

### Manual Verification
1. Run `flutter run` on Android/iOS device
2. Camera snap → frozen photo appears on TraceScreen
3. Drag TraceBox over a window in the photo — confirm smooth pan, correct mm label
4. Change wall width input — confirm scale ratio recalculates in real time
5. Tap "Generate 3D" — WebView opens, Three.js wall renders with correct hole position
6. Drag a cabinet from sidebar into scene
7. Tap "Finalize" — confirm JSON POST to `/quote` returns a PDF link

### Automated Tests
- `flutter test` unit tests for `scale_math.dart` (px/mm round-trip)
- `flutter test` unit tests for `payload_builder.dart` (JSON structure)
- `pytest backend/` for pricing calculation and PDF generation
