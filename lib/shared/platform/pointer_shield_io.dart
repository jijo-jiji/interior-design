import 'package:flutter/widgets.dart';

/// On Android the WebView takes part in Flutter's hit testing, so controls
/// over it already get their taps.
class PointerShield extends StatelessWidget {
  const PointerShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
