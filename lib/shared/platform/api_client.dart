import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The office server's answer to a request.
class ApiReply {
  const ApiReply(this.statusCode, this.body);

  final int statusCode;
  final String body;

  /// The server accepted it (200 OK or 201 Created).
  bool get ok => statusCode == 200 || statusCode == 201;

  /// The body as JSON, or null if it isn't JSON.
  Object? get json {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

/// Requests to the office server, on Android and in the browser alike.
/// Each returns null when the server can't be reached in time, so callers
/// treat "offline" and "server down" the same way: keep the work on the
/// device and try again later.
class ApiClient {
  const ApiClient._();

  static Future<ApiReply?> getJson(
    Uri url, {
    Duration timeout = const Duration(seconds: 3),
  }) =>
      _send(() => http.get(url), timeout);

  static Future<ApiReply?> postJson(
    Uri url,
    Object body, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      _send(
        () => http.post(
          url,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
        timeout,
      );

  static Future<ApiReply?> _send(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    try {
      final response = await request().timeout(timeout);
      return ApiReply(response.statusCode, response.body);
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } catch (_) {
      // Any other transport failure (DNS, TLS, refused) means "offline".
      return null;
    }
  }
}
