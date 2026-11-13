// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// A WebView stand-in for widget tests: records the JavaScript the app sends
/// to the 3D page, finishes "loading" straight away, and lets a test send
/// messages back as if they came from the page.
class FakeWebViewPlatform extends WebViewPlatform {
  FakeWebViewController? lastController;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      lastController = FakeWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _FakeWebViewWidget(params);
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  final List<String> javaScript = [];
  final Map<String, JavaScriptChannelParams> _channels = {};
  _FakeNavigationDelegate? _navigation;

  /// Delivers [message] to the app as if the 3D page had posted it.
  void sendFromPage(String channel, String message) {
    _channels[channel]!.onMessageReceived(JavaScriptMessage(message: message));
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    _channels[params.name] = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _navigation = handler as _FakeNavigationDelegate;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    _navigation?.onPageFinished?.call('about:blank');
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    this.javaScript.add(javaScript);
  }
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageFinished;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
