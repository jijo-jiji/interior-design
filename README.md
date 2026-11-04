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

