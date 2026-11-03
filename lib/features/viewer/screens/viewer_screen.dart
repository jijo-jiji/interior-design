import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/theme.dart';
import '../../../shared/config.dart';
import '../../layout/kitchen_layout_generator.dart';
import '../../layout/kitchen_layout_models.dart';
import '../models/cpq_engine.dart';
import '../widgets/closing_modal.dart';
import '../utils/offline_store.dart';

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

  /// Auto-generated layouts (A Value / B Balanced / C Premium) for this room.
  List<LayoutVariant> _variants = const [];
  String? _activeVariantKey;

  @override
  void initState() {
    super.initState();

    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(widget.jsonPayload) as Map<String, dynamic>;
      _wallData = parsed['wall'] as Map<String, dynamic>? ?? {};
      _obstacles = parsed['obstacles'] as List<dynamic>? ?? [];
      _currentStyle = parsed['style_archetype'] as String? ?? 'japandi';
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

    // Generate layouts on-device (works offline). An empty room starts on the
    // Balanced variant; a restored draft keeps its own cabinets.
    if (parsed != null) {
      try {
        _variants = const KitchenLayoutGenerator()
            .generateAll(KitchenRoom.fromPayload(parsed));
        final initial = _variants.where(
            (v) => v.tier == LayoutTier.balanced && v.modules.isNotEmpty);
        if (_placedCabinets.isEmpty && initial.isNotEmpty) {
          _activeVariantKey = initial.first.key;
          _placedCabinets.addAll(initial.first.toPlacedCabinets());
        }
      } catch (_) {
        _variants = const [];
      }
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
    var orbitJs = await rootBundle.loadString('assets/3d/OrbitControls.js');
    var html = await rootBundle.loadString('assets/3d/index.html');

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
    final escaped =
        widget.jsonPayload.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

    await _webViewController.runJavaScript("setNativeMode(true)");
    await _webViewController.runJavaScript("loadScene('$escaped')");
    if (_activeVariantKey != null) {
      await _pushCabinetsToScene();
      _showVariantWarnings(
          _variants.firstWhere((v) => v.key == _activeVariantKey));
    }
    if (mounted) setState(() => _sceneLoaded = true);
  }

  void _spawnCabinet(String type) {
    _webViewController.runJavaScript("spawnCabinet('$type')");
    HapticFeedback.lightImpact();
  }

  /// Replaces every cabinet in the 3D scene with [_placedCabinets].
  Future<void> _pushCabinetsToScene() {
    // Double-encoded: the inner JSON becomes a safe JS string literal.
    return _webViewController.runJavaScript(
        'replaceCabinets(${jsonEncode(jsonEncode(_placedCabinets))})');
  }

  void _selectVariant(LayoutVariant variant) {
    setState(() {
      _activeVariantKey = variant.key;
      _placedCabinets
        ..clear()
        ..addAll(variant.toPlacedCabinets());
    });
    _pushCabinetsToScene();
    HapticFeedback.lightImpact();
    _showVariantWarnings(variant);
  }

  void _clearLayout() {
    setState(() {
      _activeVariantKey = null;
      _placedCabinets.clear();
    });
    _pushCabinetsToScene();
    HapticFeedback.lightImpact();
  }

  void _showVariantWarnings(LayoutVariant variant) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (variant.warnings.isEmpty) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            '${variant.key} · ${variant.name}: ${variant.warnings.join(' ')}'),
        duration: const Duration(seconds: 4),
      ),
    );
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
      } else if (type == 'cabinet_moved') {
        // Keep the saved position in sync with drags in the 3D view.
        final i = _placedCabinets.indexWhere((c) => c['id'] == data['id']);
        if (i >= 0)
          _placedCabinets[i] = {..._placedCabinets[i], 'x_mm': data['x_mm']};
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
    final quoteId =
        'QT-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}';
    final payload = {
      'quote_id': quoteId,
      'wall': _wallData,
      'obstacles': _obstacles,
      'placed_cabinets': _placedCabinets,
      'salesperson_id': 'demo_agent_01',
      'style_archetype': summary.styleArchetype,
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
        _showSuccessDialog(
            result, clientName, clientPhone, depositLocked, false);
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
    final total =
        result['total_price'] ?? _cpqSummary.totalPrice.toStringAsFixed(2);
    final pdfUrl = result['pdf_url'] ?? '';

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
                color: isOfflineQueued
                    ? AppTheme.accentTerracotta.withOpacity(0.2)
                    : AppTheme.successDim,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOfflineQueued
                    ? Icons.offline_pin_rounded
                    : Icons.check_circle_rounded,
                color: isOfflineQueued ? AppTheme.accent : AppTheme.success,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isOfflineQueued
                    ? 'Locked to Offline Outbox!'
                    : 'Deal Locked & Signed!',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary),
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
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _SummaryTile(label: 'Quote Number', value: quoteId),
            _SummaryTile(label: 'Total Value', value: '\$$total AUD'),
            _SummaryTile(
              label: 'Slot Status',
              value:
                  depositLocked ? 'Priority Locked (\$250)' : 'Estimate Sent',
            ),
            _SummaryTile(
                label: 'Style Archetype', value: _cpqSummary.styleName),
            if (pdfUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SummaryTile(label: 'PDF Document', value: pdfUrl),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              final text = Uri.encodeComponent(
                'Hi $clientName! Here is your custom interior design quotation ($quoteId) '
                'for \$$total AUD in ${_cpqSummary.styleName} style. '
                'Slot status: ${depositLocked ? "Priority Locked (\$250)" : "Estimate"}.',
              );
              final cleanPhone = clientPhone.replaceAll(RegExp(r'[^\d]'), '');
              Clipboard.setData(
                  ClipboardData(text: 'https://wa.me/$cleanPhone?text=$text'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'WhatsApp proposal link generated and copied to clipboard!'),
                  backgroundColor: AppTheme.accent,
                ),
              );
            },
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('Share to WhatsApp'),
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
                  icon: const Icon(Icons.close_rounded,
                      color: AppTheme.textSecondary),
                ),
              ],
            ),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 8),
            _SummaryTile(
              label: 'Base Cabinets',
              value: '\$${summary.baseCabinetTotal.toStringAsFixed(2)}',
            ),
            _SummaryTile(
              label: 'Wall Cabinets',
              value: '\$${summary.wallCabinetTotal.toStringAsFixed(2)}',
            ),
            if (summary.tallCabinetTotal > 0)
              _SummaryTile(
                label: 'Tall Cabinets',
                value: '\$${summary.tallCabinetTotal.toStringAsFixed(2)}',
              ),
            _SummaryTile(
              label: 'Finish Multiplier (${summary.styleName})',
              value: '${summary.materialMultiplier}x',
            ),
            _SummaryTile(
              label: 'Installation Labour (${summary.totalModules} units)',
              value: '\$${summary.labourTotal.toStringAsFixed(2)}',
            ),
            if (summary.obstacleAllowance != 0)
              _SummaryTile(
                label: 'Cutout Allowance (Doors/Windows)',
                value:
                    '-\$${summary.obstacleAllowance.abs().toStringAsFixed(2)}',
              ),
            _SummaryTile(
              label: 'GST (10%)',
              value: '\$${summary.gst.toStringAsFixed(2)}',
            ),
            const Divider(color: AppTheme.border),
            _SummaryTile(
              label: 'Total Project Price',
              value: '\$${summary.totalPrice.toStringAsFixed(2)} AUD',
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
        title: const Text('3D Live Co-Design'),
        actions: [
          IconButton(
            tooltip: 'View Itemized BOQ',
            onPressed: _showBOQSheet,
            icon: const Icon(Icons.receipt_long_rounded),
          ),
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
                // ── Auto-layout variants (A / B / C) ─────────────────────
                if (_variants.isNotEmpty) ...[
                  _LayoutVariantBar(
                    variants: _variants,
                    activeKey: _activeVariantKey,
                    onSelect: _selectVariant,
                    onClear: _placedCabinets.isEmpty ? null : _clearLayout,
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Native Joinery Module Drawer ─────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _JoineryModuleButton(
                        type: 'base_800',
                        label: 'Base 800',
                        dims: '800mm',
                        icon: Icons.view_agenda_outlined,
                        onAdd: () => _spawnCabinet('base_800'),
                      ),
                      const SizedBox(width: 8),
                      _JoineryModuleButton(
                        type: 'base_600',
                        label: 'Base 600',
                        dims: '600mm',
                        icon: Icons.crop_square_rounded,
                        onAdd: () => _spawnCabinet('base_600'),
                      ),
                      const SizedBox(width: 8),
                      _JoineryModuleButton(
                        type: 'wall_600',
                        label: 'Wall 600',
                        dims: '600mm',
                        icon: Icons.table_rows_outlined,
                        onAdd: () => _spawnCabinet('wall_600'),
                      ),
                      const SizedBox(width: 8),
                      _JoineryModuleButton(
                        type: 'tall_600',
                        label: 'Tall 600',
                        dims: '2100mm',
                        icon: Icons.view_sidebar_outlined,
                        onAdd: () => _spawnCabinet('tall_600'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ── Live Dynamic Budget Odometer ─────────────────────────
                GestureDetector(
                  onTap: _showBOQSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
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
                                  TweenAnimationBuilder<double>(
                                    tween: Tween<double>(
                                        begin: 0, end: summary.totalPrice),
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, val, _) {
                                      return Text(
                                        '\$${val.toStringAsFixed(0)} AUD',
                                        style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -0.5,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceRaised,
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          Border.all(color: AppTheme.border),
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
                                    ? '\$${summary.monthlyPayment.toStringAsFixed(0)}/mo (36mo) • \$250 Slot Deposit'
                                    : 'Tap modules above to place along wall rails',
                                style: TextStyle(
                                  color:
                                      AppTheme.textSecondary.withOpacity(0.85),
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
                          icon: const Icon(Icons.receipt_long_rounded,
                              color: AppTheme.textSecondary, size: 20),
                        ),

                        const SizedBox(width: 4),

                        // Quick Closing Action Button
                        InkWell(
                          onTap: _openClosingModal,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
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
                                Icon(Icons.verified_rounded,
                                    size: 16, color: Colors.white),
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
          color:
              isSelected ? AppTheme.accent : AppTheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: AppTheme.accent.withOpacity(0.2), blurRadius: 8)
                ]
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

/// The A / B / C switcher the salesperson flips through with the client.
class _LayoutVariantBar extends StatelessWidget {
  final List<LayoutVariant> variants;
  final String? activeKey;
  final ValueChanged<LayoutVariant> onSelect;
  final VoidCallback? onClear;

  const _LayoutVariantBar({
    required this.variants,
    required this.activeKey,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final sample = variants.any((v) => v.usesPlaceholderCatalog);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 14, color: AppTheme.accent),
                const SizedBox(width: 6),
                const Text(
                  'Auto layouts',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold),
                ),
                if (sample)
                  Text(
                    '  ·  sample catalog',
                    style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.85),
                        fontSize: 10.5),
                  ),
                const Spacer(),
                if (onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < variants.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _VariantChip(
                    variant: variants[i],
                    selected: variants[i].key == activeKey,
                    onTap: () => onSelect(variants[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _VariantChip extends StatelessWidget {
  final LayoutVariant variant;
  final bool selected;
  final VoidCallback onTap;

  const _VariantChip(
      {required this.variant, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: selected ? AppTheme.accent : AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${variant.key} · ${variant.name}',
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              variant.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? Colors.white.withOpacity(0.85)
                    : AppTheme.textSecondary,
                fontSize: 9.5,
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
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.accent),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  dims,
                  style: TextStyle(
                    color: AppTheme.textSecondary.withOpacity(0.8),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded,
                  size: 12, color: AppTheme.accent),
            ),
          ],
        ),
      ),
    );
  }
}
