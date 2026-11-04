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

**Browser, served by the office server (recommended):**

```bash
./tool/build_web.sh          # Windows: .\tool\build_web.ps1
cd backend && python main.py
```

Open `http://<laptop-ip>:8000/sales/` on the tablet or laptop. The app uses
the server it was opened from, so there is nothing to configure.

**Browser, while developing:**

```bash
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8000
```

Notes for the browser:

- **Camera access:** the camera works only over `https://` or on
  `localhost`. On a plain-`http` shop network, use "Choose from gallery"
  instead (on a tablet this can still open the camera).
- **Saved designs:** kept in the browser's storage. Clearing site data
  deletes the ones not yet sent.
- **The 3D view:** runs in an iframe.

