import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../shared/theme.dart';

/// Full-screen view of the signed proposal.
///
/// This is handed to the client across the table, so the chrome stays minimal:
/// the document, a way out, and the share / print actions the preview provides.
class ProposalPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String quoteId;
  final String clientName;

  const ProposalPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.quoteId,
    required this.clientName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceRaised,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              clientName.trim().isEmpty ? 'Signed proposal' : clientName.trim(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              quoteId,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      body: PdfPreview(
        build: (_) async => pdfBytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: '$quoteId.pdf',
        // The package defaults to Material purple, which is jarring next to the
        // warm neutral palette when the tablet is facing the client.
        actionBarTheme: const PdfActionBarTheme(
          backgroundColor: AppTheme.accent,
          iconColor: AppTheme.bg,
          textStyle: TextStyle(color: AppTheme.bg),
          elevation: 0,
        ),
        loadingWidget: const Center(
          child: CircularProgressIndicator(color: AppTheme.accentTaupe),
        ),
        previewPageMargin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(8),
      ),
    );
  }
}
