import 'package:flutter/foundation.dart';

// ─── Backend Configuration ──────────────────────────────────────────────────
//
// DEMO DAY CHECKLIST (do this before leaving the office):
//
// 1. Connect your laptop AND the tablet to the SAME Wi-Fi / mobile hotspot
// 2. On your laptop, open PowerShell and run:  ipconfig
// 3. Find "IPv4 Address" under your active adapter (e.g. 192.168.1.42)
// 4. Paste that IP into [backendHost] below
// 5. Start the backend with:  python main.py
//    (it already binds to 0.0.0.0 so the tablet can reach it)
//
// ────────────────────────────────────────────────────────────────────────────

// In the browser: the office server also serves the web app (at /sales), so
// the app talks to whichever server it was opened from. When running it
// separately (`flutter run -d chrome`), point it at the server with
//   --dart-define=BACKEND_URL=http://localhost:8000
// ────────────────────────────────────────────────────────────────────────────

class AppConfig {
  AppConfig._();

  /// Set with `--dart-define=BACKEND_URL=...`; wins on every platform.
  static const String backendUrlOverride =
      String.fromEnvironment('BACKEND_URL');

  // ── Change this to your laptop's LAN IP before the demo ──────────────────
  // Android Emulator  → use '10.0.2.2'
  // Physical device   → use your laptop's IPv4 from `ipconfig`, e.g. '192.168.1.42'
  static const String backendHost = '10.0.2.2'; // ← UPDATE BEFORE DEMO

  static const int backendPort = 8000;

  static String get backendBaseUrl {
    if (backendUrlOverride.isNotEmpty) return backendUrlOverride;
    if (kIsWeb) return Uri.base.origin;
    return 'http://$backendHost:$backendPort';
  }

  static String get quoteEndpoint => '$backendBaseUrl/quote';
}
