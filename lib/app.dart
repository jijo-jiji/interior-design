import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'shared/sales_config.dart';
import 'shared/theme.dart';
import 'features/intake/screens/intake_hub_screen.dart';
import 'features/trace/screens/camera_screen.dart';
import 'features/trace/screens/wall_setup_screen.dart';
import 'features/trace/screens/trace_screen.dart';
import 'features/floorplan/screens/floorplan_calibrate_screen.dart';
import 'features/template/screens/template_room_screen.dart';
import 'features/viewer/screens/viewer_screen.dart';

// ─── Router ──────────────────────────────────────────────────────────────────

/// Screens that need what the previous screen handed over (a photo, a
/// design). In a browser, a reload or a typed address arrives without it,
/// so those go back to the home screen instead of failing.
String? _homeIfMissing(BuildContext context, GoRouterState state) =>
    state.extra is String ? null : '/';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'intake',
      builder: (context, state) => const IntakeHubScreen(),
    ),
    GoRoute(
      path: '/camera',
      name: 'camera',
      builder: (context, state) => const CameraScreen(),
    ),
    GoRoute(
      path: '/floorplan-calibrate',
      redirect: _homeIfMissing,
      name: 'floorplan-calibrate',
      builder: (context, state) => FloorplanCalibrateScreen(
        imagePath: state.extra as String,
      ),
    ),
    GoRoute(
      path: '/template-room',
      name: 'template-room',
      builder: (context, state) => const TemplateRoomScreen(),
    ),
    GoRoute(
      path: '/wall-setup',
      redirect: _homeIfMissing,
      name: 'wall-setup',
      builder: (context, state) => WallSetupScreen(
        imagePath: state.extra as String,
      ),
    ),
    GoRoute(
      path: '/trace',
      redirect: _homeIfMissing,
      name: 'trace',
      builder: (context, state) => TraceScreen(
        imagePath: state.extra as String,
      ),
    ),
    GoRoute(
      path: '/viewer',
      redirect: _homeIfMissing,
      name: 'viewer',
      builder: (context, state) => ViewerScreen(
        jsonPayload: state.extra as String,
      ),
    ),
  ],
);

// ─── App ─────────────────────────────────────────────────────────────────────

class StaticTraceApp extends StatelessWidget {
  const StaticTraceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: SalesConfig.brandName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
