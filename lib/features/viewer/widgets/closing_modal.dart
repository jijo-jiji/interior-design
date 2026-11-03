import 'package:flutter/material.dart';

import '../../../shared/labels.dart';
import '../../../shared/money.dart';
import '../../../shared/sales_config.dart';
import '../../../shared/theme.dart';
import 'signature_pad.dart';

/// Called when the salesperson saves the quote. [depositAmount] is 0 when the
/// client hasn't paid a deposit.
typedef QuoteConfirmCallback = Future<void> Function({
  required String clientName,
  required String clientPhone,
  required String clientEmail,
  required double depositAmount,
  required String? signatureBase64,
});

/// The quote sheet at the end of the meeting.
///
/// - "Save & send quote" needs only the client's name; the signature is
///   optional, so a client who wants to think it over still gets a quote.
/// - "Confirm order" (the client paid a deposit) also needs the amount and
///   the client's signature.
class ClosingModal extends StatefulWidget {
  const ClosingModal({
    super.key,
    required this.placedCabinets,
    required this.styleName,
    required this.totalPrice,
    required this.onConfirm,
    this.clientName = '',
    this.clientPhone = '',
    this.clientEmail = '',
  });

  final List<Map<String, dynamic>> placedCabinets;
  final String styleName;
  final double totalPrice;
  final QuoteConfirmCallback onConfirm;
  final String clientName;
  final String clientPhone;
  final String clientEmail;

  static Future<void> show(
    BuildContext context, {
    required List<Map<String, dynamic>> placedCabinets,
    required String styleName,
    required double totalPrice,
    required QuoteConfirmCallback onConfirm,
    String clientName = '',
    String clientPhone = '',
    String clientEmail = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClosingModal(
        placedCabinets: placedCabinets,
        styleName: styleName,
        totalPrice: totalPrice,
        onConfirm: onConfirm,
        clientName: clientName,
        clientPhone: clientPhone,
        clientEmail: clientEmail,
      ),
    );
  }

  @override
  State<ClosingModal> createState() => _ClosingModalState();
}

class _ClosingModalState extends State<ClosingModal> {
  late final _nameController = TextEditingController(text: widget.clientName);
  late final _phoneController = TextEditingController(text: widget.clientPhone);
  late final _emailController = TextEditingController(text: widget.clientEmail);
  final _depositController = TextEditingController();
  final _signatureController = SignatureController();
  bool _depositPaid = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _depositController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  void _complain(String message) {
    // Replace any message still showing, rather than queueing behind it.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
      );
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      _complain("Enter the client's name.");
      return;
    }
    var deposit = 0.0;
    if (_depositPaid) {
      deposit = parseMoney(_depositController.text) ?? 0;
      if (deposit <= 0) {
        _complain('Enter the deposit amount.');
        return;
      }
      if (_signatureController.isEmpty) {
        _complain('The client needs to sign to confirm the order.');
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final sigBase64 = await _signatureController.toBase64Png();
      await widget.onConfirm(
        clientName: _nameController.text.trim(),
        clientPhone: _phoneController.text.trim(),
        clientEmail: _emailController.text.trim(),
        depositAmount: deposit,
        signatureBase64: sigBase64,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _field(String label, IconData icon, {String? prefix}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppTheme.border),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      prefixIcon: Icon(icon, color: AppTheme.accent, size: 18),
      prefixText: prefix,
      filled: true,
      fillColor: AppTheme.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppTheme.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final cabinets =
        widget.placedCabinets.where((c) => c['kind'] != 'filler').length;
    const sectionStyle = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    return Container(
      constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.92),
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quote',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Send the quote, or confirm the order if the client '
                        'paid a deposit.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceRaised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                widget.styleName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              cabinetCountLabel(cabinets),
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Expanded(
                              child: Text(
                                'Estimated total',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatMoney(widget.totalPrice),
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Client
                  const Text('Client', style: sectionStyle),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                    ),
                    decoration: _field('Name *', Icons.person_outline),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                    ),
                    decoration:
                        _field('Phone / WhatsApp', Icons.phone_outlined),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                    ),
                    decoration: _field('Email', Icons.email_outlined),
                  ),
                  const SizedBox(height: 18),

                  // Deposit
                  // Its own Material so the switch row's tap ripple shows.
                  Material(
                    color: AppTheme.surfaceRaised,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _depositPaid
                            ? AppTheme.accentTaupe
                            : AppTheme.border,
                      ),
                    ),
                    child: SwitchListTile.adaptive(
                      value: _depositPaid,
                      activeColor: AppTheme.accent,
                      contentPadding: const EdgeInsets.only(left: 8),
                      title: const Text(
                        'Client paid a deposit',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Turns this quote into a confirmed order.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      onChanged: (v) => setState(() => _depositPaid = v),
                    ),
                  ),
                  if (_depositPaid) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _depositController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: _field(
                        'Deposit amount *',
                        Icons.payments_outlined,
                        prefix: '${SalesConfig.currency} ',
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Signature
                  Text(
                    _depositPaid
                        ? 'Client signature *'
                        : 'Client signature (optional)',
                    style: sectionStyle,
                  ),
                  const SizedBox(height: 8),
                  SignaturePad(controller: _signatureController, height: 150),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              _depositPaid
                                  ? Icons.verified_rounded
                                  : Icons.send_rounded,
                              size: 20,
                            ),
                      label: Text(
                        _isSubmitting
                            ? 'Saving…'
                            : (_depositPaid
                                ? 'Confirm order'
                                : 'Save & send quote'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
