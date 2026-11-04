import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'scene_channel.dart';

/// Android (and iOS): the 3D page runs in a WebView.
class SceneBridge {
  SceneBridge({required this.onMessage, required this.onLoaded}) {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        kSceneChannel,
        onMessageReceived: (message) => onMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => onLoaded()),
      );
  }

  /// A JSON event from the page, e.g. `{"event":"cabinet_moved",...}`.
  final ValueChanged<String> onMessage;

  /// The page has loaded and its functions can be called.
  final VoidCallback onLoaded;

  late final WebViewController _controller;
  late final Widget _view = WebViewWidget(controller: _controller);

  Future<void> loadHtml(String html) => _controller.loadHtmlString(html);

  Future<void> runJavaScript(String javaScript) =>
      _controller.runJavaScript(javaScript);

  Widget buildView() => _view;

  /// Whether touches go to the 3D view. On Android, Flutter routes touches
  /// itself, so there is nothing to do.
  void setInteractive(bool interactive) {}

  void dispose() {}
}
