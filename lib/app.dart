import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'shared/theme.dart';
import 'features/intake/screens/intake_hub_screen.dart';
import 'features/trace/screens/camera_screen.dart';
import 'features/trace/screens/wall_setup_screen.dart';
import 'features/trace/screens/trace_screen.dart';
import 'features/floorplan/screens/floorplan_calibrate_screen.dart';
import 'features/template/screens/template_room_screen.dart';
import 'features/viewer/screens/viewer_screen.dart';

// ─── Router ──────────────────────────────────────────────────────────────────

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
      name: 'wall-setup',
      builder: (context, state) => WallSetupScreen(
        imagePath: state.extra as String,
      ),
    ),
    GoRoute(
      path: '/trace',
      name: 'trace',
      builder: (context, state) => TraceScreen(
        imagePath: state.extra as String,
      ),
    ),
    GoRoute(
      path: '/viewer',
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
      title: 'Static Trace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
