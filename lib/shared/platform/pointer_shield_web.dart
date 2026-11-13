import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// In the browser the 3D view is an `<iframe>`, and pointer events that land
/// in an iframe never reach Flutter, even where a Flutter button is drawn
/// on top of it. This puts an invisible `<div>` behind [child]: events land
/// on the div instead, which belongs to the app's page, so Flutter sees them.
/// (The technique of package:pointer_interceptor.)
class PointerShield extends StatelessWidget {
  const PointerShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            isVisible: false,
            onElementCreated: (element) {
              (element as web.HTMLElement).style
                ..width = '100%'
                ..height = '100%';
            },
          ),
        ),
        child,
      ],
    );
  }
}
