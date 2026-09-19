import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/theme.dart';
import '../../../shared/config.dart';
import '../models/cpq_engine.dart';
import '../widgets/closing_modal.dart';
import '../utils/offline_store.dart';
import '../utils/proposal_delivery.dart';
import 'proposal_preview_screen.dart';

/// Touch-First 3D Viewer & Sales Closing Canvas.
/// Embeds Three.js via local WebView with:
/// 1. Magnetic cabinet snapping along wall rails
/// 2. 1-Tap Curated Style Archetypes
/// 3. Live Dynamic Budget Odometer (instant CPQ)
/// 4. On-screen client signature & deal commitment
class ViewerScreen extends StatefulWidget {
  final String jsonPayload;
  const ViewerScreen({super.key, required this.jsonPayload});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final WebViewController _webViewController;
  bool _sceneLoaded = false;
  bool _isFinalising = false;

  final List<Map<String, dynamic>> _placedCabinets = [];
  late final List<dynamic> _obstacles;
  late final Map<String, dynamic> _wallData;

  String _currentStyle = 'japandi';

  /// null = no stone quoted yet. Priced per linear metre of base/corner run.
  String? _benchtopMaterial;

  @override
  void initState() {
    super.initState();

    try {
      final parsed = jsonDecode(widget.jsonPayload) as Map<String, dynamic>;
      _wallData = parsed['wall'] as Map<String, dynamic>? ?? {};
      _obstacles = parsed['obstacles'] as List<dynamic>? ?? [];
      _currentStyle = parsed['style_archetype'] as String? ?? 'japandi';
      _benchtopMaterial = parsed['benchtop_material'] as String?;
      if (parsed['placed_cabinets'] != null) {
        final cabs = parsed['placed_cabinets'] as List<dynamic>;
        for (final c in cabs) {
          _placedCabinets.add(Map<String, dynamic>.from(c as Map));
        }
      }
    } catch (_) {
      _wallData = {};
      _obstacles = [];
    }

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'StaticTraceChannel',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectScene(),
        ),
      );

    _loadHtml();
  }

  Future<void> _loadHtml() async {
    final threeJs = await rootBundle.loadString('assets/3d/three.min.js');
    var orbitJs   = await rootBundle.loadString('assets/3d/OrbitControls.js');
    var html      = await rootBundle.loadString('assets/3d/index.html');

    if (!mounted) return;

    orbitJs = orbitJs.replaceFirst(
      RegExp(r'import\s*\{[\s\S]*?\}\s*from\s*[^;]+;\s*'),
      'var{EventDispatcher,MOUSE,Quaternion,Spherical,TOUCH,Vector2,'
      'Vector3,Plane,Ray,Raycaster,MathUtils}=THREE;',
    );
    orbitJs = orbitJs.replaceAll(
      RegExp(r'export\s*\{[^}]+\};?'),
      'window.OrbitControls=OrbitControls;',
    );

    html = html.replaceAll(
      RegExp(r'<script type="importmap">[\s\S]*?</script>\s*'),
      '',
    );
    html = html.replaceAll('<script type="module">', '<script>');
    html = html.replaceAll(
      RegExp(r"import\s*\*\s*as\s*THREE\s*from\s*'[^']*';\s*"),
      '',
    );
    html = html.replaceAll(
      RegExp(r"import\s*\{\s*OrbitControls\s*\}\s*from\s*'[^']*';\s*"),
      '',
    );
    html = html.replaceFirst(
      '</head>',
      '<script>$threeJs</script>\n<script>$orbitJs</script>\n</head>',
    );

    await _webViewController.loadHtmlString(html);
  }

  Future<void> _injectScene() async {
    final escaped = widget.jsonPayload
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'");

    await _webViewController.runJavaScript("setNativeMode(true)");
    await _webViewController.runJavaScript("loadScene('$escaped')");
    if (mounted) setState(() => _sceneLoaded = true);
  }

  void _spawnCabinet(String type) {
    _webViewController.runJavaScript("spawnCabinet('$type')");
    HapticFeedback.lightImpact();
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['event'] as String?;

      if (type == 'cabinet_placed') {
        setState(() {
          _placedCabinets.add(data);
        });
      } else if (type == 'cabinet_removed') {
        setState(() {
          _placedCabinets.removeWhere((c) => c['id'] == data['id']);
        });
      } else if (type == 'cabinet_snapped') {
        // Haptic feedback when magnetic snapping engages
        HapticFeedback.selectionClick();
      } else if (type == 'style_applied') {
        setState(() {
          _currentStyle = data['archetype'] as String? ?? _currentStyle;
        });
      }
    } catch (_) {}
  }

  void _switchStyle(String styleKey) {
    if (_currentStyle == styleKey) return;
    setState(() => _currentStyle = styleKey);
    _webViewController.runJavaScript("applyStyleArchetype('$styleKey')");
    HapticFeedback.lightImpact();
  }

  CPQSummary get _cpqSummary {
    return CPQEngine.calculate(
      placedCabinets: _placedCabinets,
      obstacles: _obstacles,
      styleArchetype: _currentStyle,
      benchtopMaterial: _benchtopMaterial,
    );
  }

  /// Appliance modules. They price like joinery (the cabinetry, cutouts and
  /// services), so they spawn through the same path as a cabinet.
  static const List<({String type, String label, String blurb, IconData icon})>
      _appliances = [
    (type: 'sink_600', label: 'Sink 600', blurb: 'Undermount bowl & tap cutout', icon: Icons.water_drop_outlined),
    (type: 'cooktop_600', label: 'Cooktop 600', blurb: 'Induction cutout & isolator', icon: Icons.local_fire_department_outlined),
    (type: 'dishwasher_600', label: 'Dishwasher 600', blurb: 'Integrated, under bench', icon: Icons.local_laundry_service_outlined),
    (type: 'oven_tower_600', label: 'Oven Tower 600', blurb: 'Wall oven + microwave stack', icon: Icons.microwave_outlined),
    (type: 'fridge_recess_700', label: 'Fridge Recess 700', blurb: 'Framed recess & panels', icon: Icons.kitchen_outlined),
    (type: 'rangehood_900', label: 'Rangehood 900', blurb: 'Wall mounted, ducted', icon: Icons.air_outlined),
  ];

  void _showApplianceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      // Six modules do not fit a default sheet on a phone — let it scroll.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Appliance',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Cabinetry, cutouts and services — appliance supply is quoted separately.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
              ..._appliances.map((item) {
                final price = CPQEngine.cabinetPrices[item.type] ?? 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      _spawnCabinet(item.type);
                      Navigator.pop(sheetContext);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Icon(item.icon, size: 20, color: AppTheme.accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.label,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  item.blurb,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '+RM${price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Benchtop chooser. The rates already existed in CPQEngine but nothing ever
  /// selected one, so every quote priced stone at zero.
  void _showBenchtopSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final metres = _cpqSummary.benchtopLinearMetres;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Benchtop Material',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metres > 0
                      ? '${metres.toStringAsFixed(2)} linear metres of run measured'
                      : 'Place base cabinets first to measure the run.',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 14),

                ...CPQEngine.benchtopRates.entries.map((entry) {
                  final selected = _benchtopMaterial == entry.key;
                  final cost = metres * entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _benchtopMaterial = entry.key);
                        HapticFeedback.selectionClick();
                        Navigator.pop(sheetContext);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.surfaceRaised : AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? AppTheme.accentTaupe : AppTheme.border,
                            width: selected ? 1.6 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 20,
                              color: selected ? AppTheme.accent : AppTheme.textTertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    CPQEngine.benchtopNames[entry.key] ?? entry.key,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'RM${entry.value.toStringAsFixed(0)} per linear metre',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              metres > 0 ? '+RM${cost.toStringAsFixed(0)}' : '—',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                if (_benchtopMaterial != null)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _benchtopMaterial = null);
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Remove benchtop from quote'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openClosingModal() {
    final summary = _cpqSummary;
    ClosingModal.show(
      context,
      wallData: _wallData,
      placedCabinets: _placedCabinets,
      styleArchetype: summary.styleArchetype,
      styleName: summary.styleName,
      totalPrice: summary.totalPrice,
      depositAmount: 250.00,
      onConfirm: _submitDeal,
    );
  }

  Future<void> _submitDeal({
    required String clientName,
    required String clientPhone,
    required String clientEmail,
    required bool depositLocked,
    required String? signatureBase64,
  }) async {
    final summary = _cpqSummary;
    final quoteId = 'QT-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}';
    final payload = {
      'quote_id': quoteId,
      'wall': _wallData,
      'obstacles': _obstacles,
      'placed_cabinets': _placedCabinets,
      'salesperson_id': 'demo_agent_01',
      'style_archetype': summary.styleArchetype,
      'benchtop_material': _benchtopMaterial,
      'client_name': clientName,
      'client_phone': clientPhone,
      'client_email': clientEmail,
      'deposit_paid': depositLocked ? 250.00 : 0.0,
      'signature_base64': signatureBase64,
    };

    // 1. Immediately secure draft in true local offline storage
    await OfflineStore.saveDraft(payload);

    try {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse(AppConfig.quoteEndpoint));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode(payload));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final result = jsonDecode(body) as Map<String, dynamic>;
      client.close();

      // Successfully synced with cloud: clear from offline outbox
      await OfflineStore.removeDraft(quoteId);

      if (mounted) {
        Navigator.pop(context); // Close modal
        _showSuccessDialog(result, clientName, clientPhone, depositLocked, false);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close modal
        // Show success with offline queue confirmation
        _showSuccessDialog({
          'quote_id': quoteId,
          'total_price': summary.totalPrice.toStringAsFixed(2),
          'pdf_url': '',
        }, clientName, clientPhone, depositLocked, true);
      }
    }
  }

  void _showSuccessDialog(
    Map<String, dynamic> result,
    String clientName,
    String clientPhone,
    bool depositLocked,
    bool isOfflineQueued,
  ) {
    final quoteId = result['quote_id'] ?? 'QT-SUCCESS';
    final total = result['total_price'] ?? _cpqSummary.totalPrice.toStringAsFixed(2);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isOfflineQueued ? AppTheme.accentTerracotta.withOpacity(0.2) : AppTheme.successDim,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOfflineQueued ? Icons.offline_pin_rounded : Icons.check_circle_rounded,
                color: isOfflineQueued ? AppTheme.accent : AppTheme.success,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isOfflineQueued ? 'Locked to Offline Outbox!' : 'Deal Locked & Signed!',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isOfflineQueued
                  ? 'Agreement & signature secured locally. Will auto-sync with studio when online.'
                  : 'Agreement successfully recorded and synced with back-office Studio.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _SummaryTile(label: 'Quote Number', value: quoteId),
            _SummaryTile(label: 'Total Value', value: 'RM$total'),
            _SummaryTile(
              label: 'Slot Status',
              value: depositLocked ? 'Priority Locked (RM250)' : 'Estimate Sent',
            ),
            _SummaryTile(label: 'Style Archetype', value: _cpqSummary.styleName),
            if (isOfflineQueued) ...[
              const SizedBox(height: 8),
              const Text(
                'The signed PDF becomes available once this quote syncs.',
                style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
              ),
            ],
          ],
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton.icon(
            onPressed: isOfflineQueued ? null : () => _openProposal(quoteId, clientName),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
            label: const Text('Open proposal'),
          ),
          TextButton.icon(
            onPressed: () => _sendToWhatsApp(
              clientName: clientName,
              clientPhone: clientPhone,
              quoteId: quoteId,
              total: '$total',
              depositLocked: depositLocked,
              isOfflineQueued: isOfflineQueued,
            ),
            icon: const Icon(Icons.chat_rounded, size: 16),
            label: const Text('Send to WhatsApp'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/');
            },
            child: const Text('New Session'),
          ),
        ],
      ),
    );
  }

  /// Downloads the signed PDF and shows it full-screen for the client.
  Future<void> _openProposal(String quoteId, String clientName) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentTerracotta),
      ),
    );

    try {
      final file = await ProposalDelivery.downloadProposalPdf(quoteId);
      navigator.pop(); // Dismiss the spinner.
      if (!mounted) return;

      navigator.push(
        MaterialPageRoute(
          builder: (_) => ProposalPreviewScreen(
            pdfFile: file,
            quoteId: quoteId,
            clientName: clientName,
          ),
        ),
      );
    } on ProposalUnavailable catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppTheme.danger),
      );
    }
  }

  /// Opens WhatsApp on the client's chat with the proposal message ready.
  Future<void> _sendToWhatsApp({
    required String clientName,
    required String clientPhone,
    required String quoteId,
    required String total,
    required bool depositLocked,
    required bool isOfflineQueued,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    final message = ProposalDelivery.buildMessage(
      clientName: clientName,
      quoteId: quoteId,
      total: total,
      styleName: _cpqSummary.styleName,
      depositLocked: depositLocked,
      isOfflineQueued: isOfflineQueued,
    );

    final result = await ProposalDelivery.sendViaWhatsApp(
      phone: clientPhone,
      message: message,
    );

    if (!mounted) return;

    final (text, colour) = switch (result) {
      WhatsAppResult.opened => ('Opening WhatsApp…', AppTheme.success),
      WhatsAppResult.openedWithoutNumber => (
          'No phone number on file — pick the contact in WhatsApp.',
          AppTheme.accent,
        ),
      WhatsAppResult.openedInBrowser => (
          'WhatsApp is not installed — opening wa.me in the browser.',
          AppTheme.accent,
        ),
      WhatsAppResult.copiedToClipboard => (
          'No app could open the link. Message copied to the clipboard.',
          AppTheme.accent,
        ),
    };

    messenger.showSnackBar(SnackBar(content: Text(text), backgroundColor: colour));
  }

  void _showBOQSheet() {
    final summary = _cpqSummary;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Itemized Bill of Quantities (BOQ)',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 8),
            _SummaryTile(
              label: 'Base Cabinets',
              value: 'RM${summary.baseCabinetTotal.toStringAsFixed(2)}',
            ),
            _SummaryTile(
              label: 'Wall Cabinets',
              value: 'RM${summary.wallCabinetTotal.toStringAsFixed(2)}',
            ),
            if (summary.tallCabinetTotal > 0)
              _SummaryTile(
                label: 'Tall Cabinets',
                value: 'RM${summary.tallCabinetTotal.toStringAsFixed(2)}',
              ),
            if (summary.benchtopTotal > 0)
              _SummaryTile(
                label:
                    '${summary.benchtopMaterial} (${summary.benchtopLinearMetres.toStringAsFixed(2)} lm)',
                value: 'RM${summary.benchtopTotal.toStringAsFixed(2)}',
              ),
            _SummaryTile(
              label: 'Finish Multiplier (${summary.styleName})',
              value: '${summary.materialMultiplier}x',
            ),
            _SummaryTile(
              label: 'Installation Labour (${summary.totalModules} units)',
              value: 'RM${summary.labourTotal.toStringAsFixed(2)}',
            ),
            if (summary.obstacleAllowance != 0)
              _SummaryTile(
                label: 'Cutout Allowance (Doors/Windows)',
                value: '-RM${summary.obstacleAllowance.abs().toStringAsFixed(2)}',
              ),
            _SummaryTile(
              label: 'SST (8%)',
              value: 'RM${summary.gst.toStringAsFixed(2)}',
            ),
            const Divider(color: AppTheme.border),
            _SummaryTile(
              label: 'Total Project Price',
              value: 'RM${summary.totalPrice.toStringAsFixed(2)}',
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _cpqSummary;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        // The BOQ button lives in the bottom HUD; repeating it here squeezed
        // the title down to "3D Live …".
        title: const Text('Co-Design'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _sceneLoaded ? _openClosingModal : null,
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: const Text('Lock In & Sign'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── 3D Viewport ─────────────────────────────────────────────────
          WebViewWidget(controller: _webViewController),

          // ── Top 1-Tap Style Archetype Selector ──────────────────────────
          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StylePill(
                    label: 'Japandi',
                    styleKey: 'japandi',
                    activeKey: _currentStyle,
                    color: const Color(0xFFC4A47C),
                    onTap: () => _switchStyle('japandi'),
                  ),
                  const SizedBox(width: 8),
                  _StylePill(
                    label: 'Minimalist',
                    styleKey: 'minimalist',
                    activeKey: _currentStyle,
                    color: const Color(0xFF2E3340),
                    onTap: () => _switchStyle('minimalist'),
                  ),
                  const SizedBox(width: 8),
                  _StylePill(
                    label: 'Nordic',
                    styleKey: 'nordic',
                    activeKey: _currentStyle,
                    color: const Color(0xFF90A48E),
                    onTap: () => _switchStyle('nordic'),
                  ),
                  const SizedBox(width: 8),
                  _StylePill(
                    label: 'Industrial',
                    styleKey: 'industrial',
                    activeKey: _currentStyle,
                    color: const Color(0xFF483C34),
                    onTap: () => _switchStyle('industrial'),
                  ),

                  // ── Appliance entry point ──────────────────────────────
                  const SizedBox(width: 14),
                  InkWell(
                    onTap: _showApplianceSheet,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.kitchen_outlined, size: 15, color: AppTheme.textSecondary),
                          SizedBox(width: 6),
                          Text(
                            'Appliances',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Benchtop entry point ───────────────────────────────
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _showBenchtopSheet,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: _benchtopMaterial != null
                            ? AppTheme.accent
                            : AppTheme.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _benchtopMaterial != null
                              ? AppTheme.accent
                              : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.countertops_outlined,
                            size: 15,
                            color: _benchtopMaterial != null
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _benchtopMaterial != null ? 'Benchtop ✓' : 'Benchtop',
                            style: TextStyle(
                              color: _benchtopMaterial != null
                                  ? Colors.white
                                  : AppTheme.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Live Dynamic Budget Odometer & Module Tray (Sticky Bottom HUD) ─
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Native Joinery Module Drawer ─────────────────────────
                // Four cards never fit a phone at their old size, so the row
                // clipped the last one mid-card. They now share the width.
                Row(
                  children: [
                    Expanded(
                      child: _JoineryModuleButton(
                        type: 'base_800',
                        label: 'Base 800',
                        dims: '800mm wide',
                        icon: Icons.view_agenda_outlined,
                        onAdd: () => _spawnCabinet('base_800'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _JoineryModuleButton(
                        type: 'base_600',
                        label: 'Base 600',
                        dims: '600mm wide',
                        icon: Icons.crop_square_rounded,
                        onAdd: () => _spawnCabinet('base_600'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _JoineryModuleButton(
                        type: 'wall_600',
                        label: 'Wall 600',
                        dims: '600mm wide, wall mounted',
                        icon: Icons.table_rows_outlined,
                        onAdd: () => _spawnCabinet('wall_600'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _JoineryModuleButton(
                        type: 'tall_600',
                        label: 'Tall 600',
                        dims: '2100mm tall',
                        icon: Icons.view_sidebar_outlined,
                        onAdd: () => _spawnCabinet('tall_600'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── Live Dynamic Budget Odometer ─────────────────────────
                GestureDetector(
                  onTap: _showBOQSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withOpacity(0.97),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2C2724).withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Dynamic Counting Price Display
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  // Four-digit totals used to push the module
                                  // chip past the edge of the HUD.
                                  Flexible(
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween<double>(begin: 0, end: summary.totalPrice),
                                      duration: const Duration(milliseconds: 400),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, val, _) {
                                        return FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'RM${val.toStringAsFixed(0)}',
                                            maxLines: 1,
                                            style: const TextStyle(
                                              color: AppTheme.textPrimary,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceRaised,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppTheme.border),
                                    ),
                                    child: Text(
                                      '${summary.totalModules} modules',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                summary.totalPrice > 0
                                    ? 'RM${summary.monthlyPayment.toStringAsFixed(0)}/mo (36mo) • RM250 Slot Deposit'
                                    : 'Tap modules above to place along wall rails',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.textSecondary.withOpacity(0.85),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Itemized BOQ Button
                        IconButton(
                          tooltip: 'Itemized BOQ',
                          onPressed: _showBOQSheet,
                          icon: const Icon(Icons.receipt_long_rounded, color: AppTheme.textSecondary, size: 20),
                        ),

                        const SizedBox(width: 4),

                        // Quick Closing Action Button
                        InkWell(
                          onTap: _openClosingModal,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accent.withOpacity(0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 16, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'Sign & Lock',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Loading overlay ─────────────────────────────────────────────
          if (!_sceneLoaded)
            const ColoredBox(
              color: AppTheme.bg,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.accent),
                    SizedBox(height: 16),
                    Text(
                      'Initialising 3D sales canvas…',
                      style: TextStyle(color: AppTheme.textSecondary),
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

class _StylePill extends StatelessWidget {
  final String label;
  final String styleKey;
  final String activeKey;
  final Color color;
  final VoidCallback onTap;

  const _StylePill({
    required this.label,
    required this.styleKey,
    required this.activeKey,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = styleKey == activeKey;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent
              : AppTheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppTheme.accent.withOpacity(0.2), blurRadius: 8)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _SummaryTile({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isBold ? AppTheme.textPrimary : AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isBold ? AppTheme.accent : AppTheme.textPrimary,
              fontSize: isBold ? 13 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _JoineryModuleButton extends StatelessWidget {
  final String type;
  final String label;
  final String dims;
  final IconData icon;
  final VoidCallback onAdd;

  const _JoineryModuleButton({
    required this.type,
    required this.label,
    required this.dims,
    required this.icon,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add $label — $dims',
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2C2724).withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppTheme.accent),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
