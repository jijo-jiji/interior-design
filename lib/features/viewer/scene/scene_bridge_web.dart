import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'scene_channel.dart';

int _bridges = 0;

/// Browser: the 3D page runs in an iframe (`srcdoc`, so it shares the app's
/// origin). The two sides talk with `postMessage`:
///  - a small script added to the page defines [kSceneChannel] so the
///    page's existing `notifyFlutter` posts its events up to the app, and
///    tells the app when the page has loaded;
///  - the app's calls arrive as messages the page runs, and only messages
///    from the app's own window are run.
class SceneBridge {
  SceneBridge({required this.onMessage, required this.onLoaded})
      : _id = 'scene-${DateTime.now().microsecondsSinceEpoch}-${_bridges++}' {
    _listener = _onWindowMessage.toJS;
    web.window.addEventListener('message', _listener);
  }

  /// A JSON event from the page, e.g. `{"event":"cabinet_moved",...}`.
  final ValueChanged<String> onMessage;

  /// The page has loaded and its functions can be called.
  final VoidCallback onLoaded;

  /// Tags this bridge's messages, so two 3D views never mix them up.
  final String _id;
  late final JSFunction _listener;

  web.HTMLIFrameElement? _frame;
  String? _html;
  bool _interactive = true;
  bool _loaded = false;
  final List<String> _waiting = [];

  late final Widget _view = HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      frame
        ..title = '3D kitchen view'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block';
      _frame = frame;
      _applyInteractive();
      final html = _html;
      if (html != null) frame.srcdoc = html.toJS;
    },
  );

  Future<void> loadHtml(String html) async {
    _loaded = false;
    _html = _withChannel(html);
    _frame?.srcdoc = _html!.toJS;
  }

  Future<void> runJavaScript(String javaScript) async {
    if (!_loaded) {
      _waiting.add(javaScript);
      return;
    }
    _frame?.contentWindow?.postMessage(
      {'bridge': _id, 'run': javaScript}.jsify(),
      web.window.location.origin.toJS,
    );
  }

  Widget buildView() => _view;

  /// Whether pointer events go to the 3D view. Off while a sheet or dialog
  /// covers it: otherwise the iframe would take the clicks meant for them.
  void setInteractive(bool interactive) {
    if (_interactive == interactive) return;
    _interactive = interactive;
    _applyInteractive();
  }

  void _applyInteractive() =>
      _frame?.style.pointerEvents = _interactive ? 'auto' : 'none';

  void dispose() {
    web.window.removeEventListener('message', _listener);
  }

  void _onWindowMessage(web.MessageEvent event) {
    final data = event.data.dartify();
    if (data is! Map || data['bridge'] != _id) return;
    if (data['loaded'] == true) {
      _loaded = true;
      final waiting = List.of(_waiting);
      _waiting.clear();
      onLoaded();
      waiting.forEach(runJavaScript);
      return;
    }
    final message = data['message'];
    if (message is String) onMessage(message);
  }

  /// Adds the channel script to the top of the page's `<head>`, before any
  /// of the page's own scripts run.
  String _withChannel(String html) {
    final script = '''
<script>
(function () {
  var id = '$_id';
  window.$kSceneChannel = {
    postMessage: function (message) {
      parent.postMessage({ bridge: id, message: String(message) }, '*');
    }
  };
  window.addEventListener('message', function (e) {
    if (e.source !== parent || !e.data || e.data.bridge !== id) return;
    if (typeof e.data.run === 'string') (0, eval)(e.data.run);
  });
  window.addEventListener('load', function () {
    parent.postMessage({ bridge: id, loaded: true }, '*');
  });
})();
</script>''';
    return html.contains('<head>')
        ? html.replaceFirst('<head>', '<head>$script')
        : '$script$html';
  }
}
