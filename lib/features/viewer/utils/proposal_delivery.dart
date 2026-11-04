import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/config.dart';

/// Handing the finished proposal to the client.
///
/// Both paths used to be dead ends: the WhatsApp button only copied a link to
/// the clipboard, and the signed PDF was shown as a URL the salesperson had no
/// way to open. This turns them into real handovers.
class ProposalDelivery {
  ProposalDelivery._();

  /// Message the client receives. Keep it short — it is read on a phone,
  /// usually while the consultant is still in the room.
  static String buildMessage({
    required String clientName,
    required String quoteId,
    required String total,
    required String styleName,
    required bool depositLocked,
    required bool isOfflineQueued,
  }) {
    final greeting =
        clientName.trim().isEmpty ? 'Hi!' : 'Hi ${clientName.trim()}!';
    final status = depositLocked
        ? 'Your build slot is locked in with the RM250 priority deposit.'
        : 'This estimate holds for 30 days.';

    final buffer = StringBuffer()
      ..writeln('$greeting Here is your $styleName kitchen design.')
      ..writeln()
      ..writeln('Quote $quoteId — RM$total incl. SST')
      ..writeln(status);

    // An offline draft has no server record yet, so sending a portal link that
    // 404s would look worse than sending none.
    if (!isOfflineQueued) {
      buffer
        ..writeln()
        ..writeln('View it in 3D: ${AppConfig.portalUrl(quoteId)}');
    }

    return buffer.toString().trim();
  }

  /// Opens WhatsApp with the message ready to send.
  ///
  /// The `whatsapp://` scheme is tried first so the installed app is used
  /// directly; a bare https://wa.me link resolves to whatever browser is
  /// registered when WhatsApp is absent, which is not the same thing.
  static Future<WhatsAppResult> sendViaWhatsApp({
    required String phone,
    required String message,
  }) async {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    final encoded = Uri.encodeComponent(message);
    final phoneParam = digits.isEmpty ? '' : 'phone=$digits&';

    final appUri = Uri.parse('whatsapp://send?${phoneParam}text=$encoded');
    // In a browser the app scheme can't be checked; wa.me hands off to the
    // app on a phone or to WhatsApp Web on a laptop.
    if (!kIsWeb && await _tryLaunch(appUri)) {
      // Without a number WhatsApp opens on its contact picker.
      return digits.isEmpty
          ? WhatsAppResult.openedWithoutNumber
          : WhatsAppResult.opened;
    }

    // wa.me works in a browser and offers to hand off to WhatsApp Web.
    final webUri = digits.isEmpty
        ? Uri.parse('https://wa.me/?text=$encoded')
        : Uri.parse('https://wa.me/$digits?text=$encoded');
    if (await _tryLaunch(webUri)) {
      return WhatsAppResult.openedInBrowser;
    }

    await Clipboard.setData(ClipboardData(text: '$message\n\n$webUri'));
    return WhatsAppResult.copiedToClipboard;
  }

  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }

  /// Downloads the signed proposal so it can be previewed, shared or printed.
  /// Throws [ProposalUnavailable] with a message fit to show the salesperson.
  /// Works on Android and in a browser (no files involved).
  static Future<Uint8List> downloadProposalPdf(String quoteId) async {
    final http.Response response;
    try {
      response = await http
          .get(Uri.parse(AppConfig.pdfEndpoint(quoteId)))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const ProposalUnavailable('Cannot reach the studio.');
    } catch (_) {
      throw const ProposalUnavailable(
        'Cannot reach the studio. Reconnect and try again.',
      );
    }
    if (response.statusCode == 404) {
      throw const ProposalUnavailable(
        'The studio has not generated this proposal yet.',
      );
    }
    if (response.statusCode != 200) {
      throw ProposalUnavailable(
        'The studio returned an error (${response.statusCode}).',
      );
    }
    return response.bodyBytes;
  }

  /// In a browser, the browser's own PDF viewer (new tab) prints and saves.
  static Future<bool> openProposalInBrowser(String quoteId) =>
      _tryLaunchWeb(Uri.parse(AppConfig.pdfEndpoint(quoteId)));

  static Future<bool> _tryLaunchWeb(Uri uri) async {
    try {
      return await launchUrl(uri, webOnlyWindowName: '_blank');
    } on PlatformException {
      return false;
    }
  }
}

enum WhatsAppResult {
  /// WhatsApp opened on the client's chat.
  opened,

  /// WhatsApp opened, but the consultant must pick the contact (no number).
  openedWithoutNumber,

  /// WhatsApp is not installed — wa.me opened in a browser instead.
  openedInBrowser,

  /// Nothing could handle the link — the message is on the clipboard.
  copiedToClipboard,
}

class ProposalUnavailable implements Exception {
  final String message;
  const ProposalUnavailable(this.message);

  @override
  String toString() => message;
}
