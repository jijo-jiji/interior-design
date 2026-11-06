import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/theme.dart';
import '../../../shared/config.dart';
import '../../../shared/labels.dart';
import '../../../shared/money.dart';
import '../../../shared/platform/pointer_shield.dart';
import '../../../shared/platform/api_client.dart';
import '../../../shared/project_status.dart';
import '../../../shared/sales_config.dart';
import '../../../shared/widgets/nudge_buttons.dart';
import '../../catalog/price_catalog.dart';
import '../../intake/providers/consultation_provider.dart';
import '../../layout/kitchen_layout_generator.dart';
import '../../layout/kitchen_layout_models.dart';
import '../models/cpq_engine.dart';
import '../models/scene_look.dart';
import '../scene/finish_textures.dart';
import '../scene/scene_bridge.dart';
import '../utils/design_pictures.dart';
import '../utils/proposal_delivery.dart';
import '../widgets/closing_modal.dart';
import '../widgets/pictures_sheet.dart';
import 'proposal_preview_screen.dart';
import '../utils/offline_store.dart';

/// The 3D design screen the salesperson shares with the client.
///
/// Embeds Three.js in a local WebView (works offline) with auto-generated
/// layouts, style switching and a live estimate. The design is saved on the
/// phone after every change; the price stays hidden until the salesperson
/// shows it; the quote sheet sends a quote or confirms an order.
/// Each Move left / Move right tap slides the selected cabinet this far.
const int kCabinetNudgeMm = 50;

class ViewerScreen extends ConsumerStatefulWidget {
  final String jsonPayload;
  const ViewerScreen({super.key, required this.jsonPayload});

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  late final SceneBridge _scene;
  bool _sceneLoaded = false;

  // Who this design is for. The quote number stays the same across every
  // auto-save and when the quote is sent, so there is one record per client.
  late final String _quoteId;
  String _clientName = '';
  String _clientPhone = '';
  String _clientEmail = '';
  ProjectStatus _status = ProjectStatus.draft;
  double _depositPaid = 0;

  /// The estimate stays hidden until the salesperson chooses to show it:
  /// clients see the design first, price after.
  bool _priceVisible = false;

  Timer? _saveTimer;

  /// How the design is dressed: doors, backsplash, decor and light.
  SceneLook _look = const SceneLook();

  /// Calls waiting for the 3D page to send pictures, by request id: 'app' is
  /// a quick capture, 'render' a realistic render.
  final Map<String, Completer<List<String>>> _pictureRequests = {};

  /// How far a render has got (0 to 1); null when none is running.
  final ValueNotifier<double?> _renderProgress = ValueNotifier(null);
  bool _rendering = false;

  /// Goes up with every change to the design, so a render made earlier can
  /// be told from one of the design as it is now.
  int _designRevision = 0;
  ({int revision, List<String> images})? _rendered;

  /// How many frames a render averages: more is smoother and slower.
  /// (`--dart-define=RENDER_SAMPLES=n` changes it, for testing.)
  static const _renderSamples =
      int.fromEnvironment('RENDER_SAMPLES', defaultValue: 40);

  /// The office has pictures of this design (sent with the quote), so the
  /// message to the client can link to them.
  bool _picturesAttached = false;

  /// Layouts mode (default) or Edit mode (add, move and remove cabinets).
  /// Outside Edit, touching the 3D only looks around.
  bool _editing = false;
  String? _selectedId;
  String? _selectedLabel;

  /// Benchtop chosen for the quote (a key of CPQEngine.benchtopRates), or
  /// none. Priced per linear metre of base run.
  String? _benchtopMaterial;

  // Return-wall (L-shape) cabinets can be selected but not moved yet.
  bool _selectedMovable = true;

  /// Full view hides every control so the client sees the whole design.
  bool _controlsHidden = false;

  final List<Map<String, dynamic>> _placedCabinets = [];
  late final List<dynamic> _obstacles;
  late final Map<String, dynamic> _wallData;

  /// The floor plan this room was read from, for the Room and House views
  /// (see FloorplanSizesScreen); null for rooms measured another way.
  Map<String, dynamic>? _floorPlan;

  /// 'kitchen', 'room' or 'house': how much of the plan the 3D shows.
  String _roomView = 'kitchen';

  void _setRoomView(String view) {
    setState(() => _roomView = view);
    _scene.runJavaScript("setRoomView('$view')");
  }

  String _currentStyle = 'japandi';

  /// The catalogue this design was opened with. A newer one arriving from the
  /// office mid-meeting waits for the next design, so the price on screen
  /// never moves under the client and always matches the version recorded on
  /// the quote.
  final PriceCatalog _catalog = PriceCatalog.current;

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
      _floorPlan = parsed['floor_plan'] as Map<String, dynamic>?;
      _currentStyle = parsed['style_archetype'] as String? ?? 'japandi';
      _benchtopMaterial = parsed['benchtop_material'] as String?;
      _look = SceneLook.fromJson(parsed['scene']);
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

    // A reopened project carries its own quote number and client; a new one
    // takes them from the client entered at the start.
    final consultation = ref.read(consultationProvider);
    final savedQuoteId = parsed?['quote_id'] as String? ?? '';
    final reopened = savedQuoteId.isNotEmpty;
    _quoteId =
        reopened ? savedQuoteId : (consultation?.quoteId ?? newQuoteId());
    _clientName = reopened
        ? (parsed?['client_name'] as String? ?? '')
        : (consultation?.clientName ?? '');
    _clientPhone = reopened
        ? (parsed?['client_phone'] as String? ?? '')
        : (consultation?.clientPhone ?? '');
    _clientEmail = parsed?['client_email'] as String? ?? '';
    _depositPaid = (parsed?['deposit_paid'] as num?)?.toDouble() ?? 0;
    if (reopened) _status = ProjectStatus.of(parsed!);

    // Generate layouts on-device (works offline). An empty room starts on the
    // Balanced variant; a restored draft keeps its own cabinets.
    if (parsed != null) {
      try {
        _variants = KitchenLayoutGenerator.forCatalog(_catalog)
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

    _scene = SceneBridge(onMessage: _onJsMessage, onLoaded: _injectScene);

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

    await _scene.loadHtml(html);
  }

  /// The catalogue's modules as the 3D page needs them: sizes and how each
  /// is drawn, so a size edited in the Studio is what the client sees.
  String _catalogModulesJson() => jsonEncode([
        for (final m in _catalog.modules)
          {
            'type': m.type,
            'label': m.label,
            'width_mm': m.widthMm,
            'height_mm': m.heightMm,
            'depth_mm': m.depthMm,
            'mount_mm': m.mountMm,
            'kind': _catalog.kindOf(m.type),
          },
      ]);

  /// Puts [_look] on the 3D view.
  Future<void> _applyLook() async {
    for (final call in _look.javaScript) {
      await _scene.runJavaScript(call);
    }
  }

  void _setLook(SceneLook look) {
    if (look == _look) return;
    setState(() => _look = look);
    _applyLook();
    _scheduleSave();
  }

  /// The Look button: doors, backsplash, decor and light.
  void _showLookSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void change(SceneLook look) {
            _setLook(look);
            setSheetState(() {});
          }

          Widget choices(String label, Map<String, String> options,
                  String selected, void Function(String) onPick) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in options.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: selected == entry.key,
                            onSelected: (_) => onPick(entry.key),
                          ),
                      ],
                    ),
                  ],
                ),
              );

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Look of the design',
                      style: context.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'How it is shown in 3D and in the pictures. None of this '
                    'changes the price.',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  choices('Doors', SceneLook.doorOptions, _look.doors,
                      (v) => change(_look.copyWith(doors: v))),
                  choices(
                      'Backsplash',
                      SceneLook.backsplashOptions,
                      _look.backsplash,
                      (v) => change(_look.copyWith(backsplash: v))),
                  choices('Light', SceneLook.moodOptions, _look.mood,
                      (v) => change(_look.copyWith(mood: v))),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show decor'),
                    subtitle: const Text(
                        'Plates, jars, plants on the worktop. Not included '
                        'in the quote.'),
                    value: _look.decor,
                    onChanged: (v) => change(_look.copyWith(decor: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show the room'),
                    subtitle: const Text(
                        'Walls, ceiling and lights around the kitchen. Not '
                        'included in the quote.'),
                    value: _look.room,
                    onChanged: (v) => change(_look.copyWith(room: v)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Puts the chosen benchtop on the worktop in the 3D view (none: the
  /// style's own).
  Future<void> _showBenchtop() =>
      _scene.runJavaScript('setBenchtop(${jsonEncode(_benchtopMaterial)})');

  Future<void> _injectScene() async {
    final escaped =
        widget.jsonPayload.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

    await _scene.runJavaScript("setNativeMode(true)");
    await _scene.runJavaScript(
        'setCatalogModules(${jsonEncode(_catalogModulesJson())})');
    // Photographs of the finishes; without them the page draws its own.
    await FinishTextures.send(_scene.runJavaScript);
    await _scene.runJavaScript("loadScene('$escaped')");
    await _showBenchtop();
    await _applyLook();
    if (_activeVariantKey != null) {
      await _pushCabinetsToScene();
      _showVariantWarnings(
          _variants.firstWhere((v) => v.key == _activeVariantKey));
      _scheduleSave();
    }
    if (mounted) setState(() => _sceneLoaded = true);
  }

  // In the browser the 3D view would take clicks meant for anything drawn
  // over it. It stops taking them while a sheet or dialog is open (this
  // screen isn't the current route then) or a message with a button shows.
  bool _routeIsCurrent = true;
  int _snackBarsWithActions = 0;

  void _updateScenePointer() =>
      _scene.setInteractive(_routeIsCurrent && _snackBarsWithActions == 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _updateScenePointer();
  }

  @override
  void dispose() {
    if (_saveTimer != null) _saveNow(); // don't lose the last change
    _scene.dispose();
    _renderProgress.dispose();
    super.dispose();
  }

  // ── Auto-save ───────────────────────────────────────────────────────────

  /// Saves the design on the phone shortly after every change, so nothing is
  /// lost if the meeting ends without a quote.
  void _scheduleSave() {
    _designRevision++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_placedCabinets.isEmpty) return;
    await OfflineStore.saveDraft(_projectRecord());
  }

  Map<String, dynamic> _projectRecord({String? signatureBase64}) {
    final summary = _cpqSummary;
    return {
      'quote_id': _quoteId,
      'status': _status.name,
      'wall': _wallData,
      'obstacles': _obstacles,
      if (_floorPlan != null) 'floor_plan': _floorPlan,
      'placed_cabinets': _placedCabinets,
      'salesperson_id': 'demo_agent_01',
      'style_archetype': summary.styleArchetype,
      'benchtop_material': _benchtopMaterial,
      'scene': _look.toJson(),
      'client_name': _clientName,
      'client_phone': _clientPhone,
      'client_email': _clientEmail,
      'deposit_paid': _depositPaid,
      'total_price': summary.totalPrice,
      // The server prices with this version, so the signed PDF matches the
      // number shown here even if the catalogue changed since.
      'catalog_version': summary.catalogVersion,
      if (signatureBase64 != null) 'signature_base64': signatureBase64,
    };
  }

  /// Cabinets the client would count (fillers are trim, not cabinets).
  int get _cabinetCount =>
      _placedCabinets.where((c) => c['kind'] != 'filler').length;

  void _spawnCabinet(String type) {
    _scene.runJavaScript("spawnCabinet('$type')");
    HapticFeedback.lightImpact();
  }

  /// Replaces every cabinet in the 3D scene with [_placedCabinets].
  Future<void> _pushCabinetsToScene() {
    // Double-encoded: the inner JSON becomes a safe JS string literal.
    return _scene.runJavaScript(
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
    _scheduleSave();
  }

  void _clearLayout() {
    final previous = List<Map<String, dynamic>>.from(_placedCabinets);
    final previousVariant = _activeVariantKey;
    setState(() {
      _activeVariantKey = null;
      _placedCabinets.clear();
      _selectedId = null;
      _selectedLabel = null;
    });
    _pushCabinetsToScene();
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    _snackBarsWithActions++;
    _updateScenePointer();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('All cabinets cleared.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                setState(() {
                  _placedCabinets
                    ..clear()
                    ..addAll(previous);
                  _activeVariantKey = previousVariant;
                });
                _pushCabinetsToScene();
                _scheduleSave();
              },
            ),
          ),
        )
        .closed
        .then((_) {
      _snackBarsWithActions--;
      if (mounted) _updateScenePointer();
    });
  }

  void _setEditing(bool editing) {
    setState(() {
      _editing = editing;
      if (!editing) {
        _selectedId = null;
        _selectedLabel = null;
      }
    });
    _scene.runJavaScript('setEditMode($editing)');
    HapticFeedback.selectionClick();
  }

  void _removeSelected() {
    _scene.runJavaScript('removeSelectedCabinet()');
    HapticFeedback.lightImpact();
  }

  // The no-drag way to choose and move cabinets (WCAG 2.5.7 and 2.1.1). The
  // page answers with cabinet_selected / cabinet_moved, as for a tap or drag.
  void _selectAdjacent(int direction) {
    _scene.runJavaScript('selectAdjacentCabinet($direction)');
    HapticFeedback.selectionClick();
  }

  void _nudgeSelected(int direction) {
    _scene
        .runJavaScript('nudgeSelectedCabinet(${direction * kCabinetNudgeMm})');
    HapticFeedback.selectionClick();
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

  void _onJsMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      switch (data['event'] as String?) {
        case 'pictures':
          _pictureRequests
              .remove(data['request_id'] as String? ?? 'app')
              ?.complete([
            for (final image in (data['images'] as List? ?? const []))
              if (image is String) image,
          ]);
        case 'render_progress':
          _renderProgress.value = (data['fraction'] as num?)?.toDouble();
        case 'cabinet_placed':
          setState(() {
            _placedCabinets.add(data);
            _activeVariantKey = null; // now the salesperson's own layout
          });
          _scheduleSave();
        case 'cabinet_removed':
          setState(() {
            _placedCabinets.removeWhere((c) => c['id'] == data['id']);
            _activeVariantKey = null;
            if (_selectedId == data['id']) {
              _selectedId = null;
              _selectedLabel = null;
            }
          });
          _scheduleSave();
        case 'cabinet_moved':
          // Keep the saved position in sync with drags in the 3D view.
          final i = _placedCabinets.indexWhere((c) => c['id'] == data['id']);
          if (i >= 0) {
            setState(() {
              _placedCabinets[i] = {
                ..._placedCabinets[i],
                'x_mm': data['x_mm'],
              };
              _activeVariantKey = null;
            });
            _scheduleSave();
          }
        case 'cabinet_selected':
          setState(() {
            _selectedId = data['id'] as String?;
            _selectedLabel = data['label'] as String?;
            _selectedMovable = data['movable'] as bool? ?? true;
          });
        case 'cabinet_deselected':
          setState(() {
            _selectedId = null;
            _selectedLabel = null;
          });
        case 'cabinet_snapped':
          HapticFeedback.selectionClick();
        case 'style_applied':
          setState(() {
            _currentStyle = data['archetype'] as String? ?? _currentStyle;
          });
      }
    } catch (_) {}
  }

  void _switchStyle(String styleKey) {
    if (_currentStyle == styleKey) return;
    setState(() => _currentStyle = styleKey);
    _scene.runJavaScript("applyStyleArchetype('$styleKey')");
    HapticFeedback.lightImpact();
    _scheduleSave();
  }

  CPQSummary get _cpqSummary {
    return CPQEngine.calculate(
      placedCabinets: _placedCabinets,
      obstacles: _obstacles,
      styleArchetype: _currentStyle,
      benchtopMaterial: _benchtopMaterial,
      catalog: _catalog,
    );
  }

  /// What an appliance line says about itself, by how it is drawn. The
  /// modules, sizes and prices come from the catalogue; this is wording.
  static ({String blurb, IconData icon}) _applianceInfo(String kind) =>
      switch (kind) {
        'sink' => (
            blurb: 'Undermount bowl and tap cutout',
            icon: Icons.water_drop_outlined
          ),
        'hob' => (
            blurb: 'Induction cutout and isolator',
            icon: Icons.local_fire_department_outlined
          ),
        'dishwasher' => (
            blurb: 'Integrated, under the worktop',
            icon: Icons.local_laundry_service_outlined
          ),
        'oven' => (
            blurb: 'Wall oven and microwave stack',
            icon: Icons.microwave_outlined
          ),
        'fridge' => (
            blurb: 'Framed recess and panels',
            icon: Icons.kitchen_outlined
          ),
        'hood' => (blurb: 'Wall mounted, ducted', icon: Icons.air_outlined),
        _ => (blurb: 'Cabinetry and services', icon: Icons.build_outlined),
      };

  void _showApplianceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add an appliance', style: context.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Prices cover the cabinetry, cutouts and services. The '
                'appliance itself is quoted separately.',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              for (final item in _catalog.applianceModules)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_applianceInfo(_catalog.kindOf(item.type)).icon,
                      color: AppTheme.accent),
                  title: Text(item.label),
                  subtitle:
                      Text(_applianceInfo(_catalog.kindOf(item.type)).blurb),
                  trailing: Text(
                    formatMoney(item.price),
                    style: context.textTheme.labelLarge,
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _spawnCabinet(item.type);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBenchtopSheet() {
    final metres = _cpqSummary.benchtopLinearMetres;
    void choose(String? material) {
      setState(() => _benchtopMaterial = material);
      _showBenchtop();
      HapticFeedback.selectionClick();
      _scheduleSave();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Benchtop', style: context.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                metres > 0
                    ? '${metres.toStringAsFixed(2)} metres of worktop measured'
                    : 'Add base cabinets first to measure the worktop.',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              for (final entry in _catalog.benchtopOptions.entries)
                RadioListTile<String?>(
                  contentPadding: EdgeInsets.zero,
                  value: entry.key,
                  groupValue: _benchtopMaterial,
                  onChanged: (v) {
                    choose(v);
                    Navigator.pop(sheetContext);
                  },
                  title: Text(entry.value.name),
                  subtitle:
                      Text('${formatMoney(entry.value.ratePerM)} per metre'),
                  secondary: Text(
                    metres > 0
                        ? '+${formatMoney(metres * entry.value.ratePerM)}'
                        : '—',
                    style: context.textTheme.labelLarge,
                  ),
                ),
              RadioListTile<String?>(
                contentPadding: EdgeInsets.zero,
                value: null,
                groupValue: _benchtopMaterial,
                onChanged: (v) {
                  choose(null);
                  Navigator.pop(sheetContext);
                },
                title: const Text('No benchtop in this quote'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The signed proposal: the browser's own PDF viewer on the web, an
  /// in-app preview (print and share) on Android.
  Future<void> _openProposal() async {
    final messenger = ScaffoldMessenger.of(context);
    if (kIsWeb) {
      final opened = await ProposalDelivery.openProposalInBrowser(_quoteId);
      if (!opened) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                "Couldn't open the proposal. Allow pop-ups and try again.")));
      }
      return;
    }
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      ),
    );
    try {
      final bytes = await ProposalDelivery.downloadProposalPdf(_quoteId);
      navigator.pop(); // the spinner
      if (!mounted) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => ProposalPreviewScreen(
          pdfBytes: bytes,
          quoteId: _quoteId,
          clientName: _clientName,
        ),
      ));
    } on ProposalUnavailable catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppTheme.danger),
      );
    }
  }

  /// Opens WhatsApp on the client's chat with the proposal message ready.
  Future<void> _sendToWhatsApp(
      {required double total, required bool sent}) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = ProposalDelivery.buildMessage(
      clientName: _clientName,
      quoteId: _quoteId,
      total: formatMoney(total).replaceFirst('${SalesConfig.currency} ', ''),
      styleName: _cpqSummary.styleName,
      depositLocked: _status == ProjectStatus.deposit,
      isOfflineQueued: !sent,
      picturesUrl:
          _picturesAttached ? AppConfig.picturesPageUrl(_quoteId) : null,
    );
    final result = await ProposalDelivery.sendViaWhatsApp(
      phone: _clientPhone,
      message: message,
    );
    if (!mounted) return;
    final text = switch (result) {
      WhatsAppResult.opened => 'Opening WhatsApp…',
      WhatsAppResult.openedWithoutNumber =>
        'No phone number saved. Pick the contact in WhatsApp.',
      WhatsAppResult.openedInBrowser => 'Opening WhatsApp in the browser…',
      WhatsAppResult.copiedToClipboard =>
        "Couldn't open WhatsApp. The message is copied: paste it in a chat.",
    };
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Asks the 3D page for pictures and waits for its answer. Empty if the
  /// page doesn't answer in time (or is busy with a render).
  Future<List<String>> _pictureCall(
      String id, String javaScript, Duration timeout) {
    final request = _pictureRequests[id] = Completer<List<String>>();
    unawaited(_scene.runJavaScript(javaScript));
    return request.future.timeout(timeout, onTimeout: () {
      _pictureRequests.remove(id);
      return const [];
    });
  }

  /// Takes the front and angled pictures of the design in the 3D view.
  Future<List<String>> _capturePictures() async {
    if (!_sceneLoaded) return const [];
    return _pictureCall(
        'app', "capturePictures('app')", const Duration(seconds: 20));
  }

  /// The slower, softer-lit version of the same two pictures. Null if it was
  /// cancelled or the view couldn't make it.
  Future<List<String>?> _renderPictures() async {
    if (!_sceneLoaded || _rendering) return null;
    setState(() => _rendering = true);
    _renderProgress.value = 0;
    final images = await _pictureCall(
      'render',
      "renderPictures('render', {samples: $_renderSamples})",
      const Duration(minutes: 10),
    );
    if (images.isEmpty) {
      // Gave up waiting: tell the page to stop too.
      unawaited(_scene.runJavaScript('cancelRender()'));
    }
    _renderProgress.value = null;
    if (mounted) setState(() => _rendering = false);
    if (images.isEmpty) return null;
    _rendered = (revision: _designRevision, images: images);
    return images;
  }

  /// The render of the design as it is now, if there is one.
  List<String>? get _currentRender =>
      _rendered != null && _rendered!.revision == _designRevision
          ? _rendered!.images
          : null;

  /// The Pictures button: pictures to show the client, and to send on.
  Future<void> _takePictures() async {
    final messenger = ScaffoldMessenger.of(context);
    var images = _currentRender;
    final alreadyRendered = images != null;
    if (images == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Taking pictures…'),
          duration: Duration(seconds: 2),
        ));
      images = await _capturePictures();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
    }
    final usable = [
      for (final image in images)
        if (DesignPictures.decode(image) != null) image,
    ];
    if (usable.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't take the pictures. Try again."),
      ));
      return;
    }

    // Both ways of sending go through the office, which keeps the pictures
    // and gives the client a page to open.
    Future<String?> pageUrl(List<String> shown) async {
      final url = await DesignPictures.upload(_quoteId, shown);
      if (url == null && mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't reach the office. Try again when you're "
              'online.'),
        ));
      }
      return url;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PicturesSheet(
        initial: usable,
        initiallyRendered: alreadyRendered,
        progress: _renderProgress,
        onRender: _renderPictures,
        onCancelRender: () => _scene.runJavaScript('cancelRender()'),
        onSendWhatsApp: (shown) async {
          final url = await pageUrl(shown);
          if (url == null) return;
          final name = _clientName.trim();
          await ProposalDelivery.sendViaWhatsApp(
            phone: _clientPhone,
            message: '${name.isEmpty ? 'Hi!' : 'Hi $name!'} Here are pictures '
                'of your kitchen design: $url',
          );
        },
        onOpenToSave: (shown) async {
          final url = await pageUrl(shown);
          if (url != null) await ProposalDelivery.openPage(url);
        },
      ),
    );
  }

  void _openClosingModal() {
    final summary = _cpqSummary;
    ClosingModal.show(
      context,
      placedCabinets: _placedCabinets,
      styleName: summary.styleName,
      totalPrice: summary.totalPrice,
      clientName: _clientName,
      clientPhone: _clientPhone,
      clientEmail: _clientEmail,
      onConfirm: _submitQuote,
    );
  }

  Future<void> _submitQuote({
    required String clientName,
    required String clientPhone,
    required String clientEmail,
    required double depositAmount,
    required String? signatureBase64,
  }) async {
    _clientName = clientName;
    _clientPhone = clientPhone;
    _clientEmail = clientEmail;
    _depositPaid = depositAmount;
    _status = depositAmount > 0 ? ProjectStatus.deposit : ProjectStatus.quote;
    _saveTimer?.cancel();
    _saveTimer = null;
    final summary = _cpqSummary;
    final record = _projectRecord(signatureBase64: signatureBase64);
    // The quote PDF and the client's page show the design as pictures.
    final pictures = _currentRender ?? await _capturePictures();
    final toSend = {
      ...record,
      if (pictures.isNotEmpty) 'design_images': pictures,
    };

    // Saved on the phone first, so nothing is lost if the network fails.
    // (Without the pictures: they are large, and a draft is saved often.)
    await OfflineStore.saveDraft(record);

    var sent = false;
    var pdfUrl = '';
    // Offline or the office server is unreachable: it stays queued.
    final reply = await ApiClient.postJson(
      Uri.parse(AppConfig.quoteEndpoint),
      toSend,
      timeout: const Duration(seconds: 20),
    );
    if (reply == null || !reply.ok) {
      // Waiting to be sent: keep the pictures with it when they fit.
      if (pictures.isNotEmpty && DesignPictures.fitsOffline(pictures)) {
        await OfflineStore.saveDraft(toSend);
      }
    }
    // Only drop the device copy once the office has actually accepted it.
    if (reply != null && reply.ok) {
      _picturesAttached = pictures.isNotEmpty;
      final result = reply.json;
      if (result is Map<String, dynamic>) {
        pdfUrl = result['pdf_url'] as String? ?? '';
      }
      sent = true;
      await OfflineStore.removeDraft(_quoteId);
    }

    if (!mounted) return;
    Navigator.pop(context); // close the quote sheet
    _showSavedDialog(total: summary.totalPrice, pdfUrl: pdfUrl, sent: sent);
  }

  void _showSavedDialog({
    required double total,
    required String pdfUrl,
    required bool sent,
  }) {
    final confirmed = _status == ProjectStatus.deposit;
    final styleName = _cpqSummary.styleName;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppTheme.successDim,
                shape: BoxShape.circle,
              ),
              child: Icon(
                sent ? Icons.check_circle_rounded : Icons.offline_pin_rounded,
                color: AppTheme.success,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                confirmed ? 'Order confirmed' : 'Quote saved',
                style: context.textTheme.titleMedium
                    ?.copyWith(color: context.colors.onSurface),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sent
                  ? 'Saved and sent to the office.'
                  : "Saved on this phone. It will be sent to the office when "
                      "you're back online.",
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            _SummaryTile(label: 'Quote number', value: _quoteId),
            _SummaryTile(label: 'Estimated total', value: formatMoney(total)),
            if (confirmed)
              _SummaryTile(label: 'Deposit', value: formatMoney(_depositPaid)),
            _SummaryTile(label: 'Style', value: styleName),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _sendToWhatsApp(total: total, sent: sent),
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: const Text('Send to WhatsApp'),
          ),
          // Only once the office has made the signed PDF.
          if (sent && pdfUrl.isNotEmpty)
            TextButton.icon(
              onPressed: _openProposal,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Open proposal'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back to design'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(consultationProvider.notifier).state = null;
              context.go('/');
            },
            child: const Text('New client'),
          ),
        ],
      ),
    );
  }

  void _showBOQSheet() {
    final summary = _cpqSummary;
    // Opening the breakdown is a deliberate reveal.
    if (!_priceVisible) setState(() => _priceVisible = true);
    final taxPercent = (_catalog.taxRate * 100).round();
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
                Text(
                  'Price breakdown',
                  style: context.textTheme.titleSmall
                      ?.copyWith(color: context.colors.onSurface),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: AppTheme.textSecondary),
                ),
              ],
            ),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 8),
            _SummaryTile(
              label: 'Base cabinets',
              value: formatMoney(summary.baseCabinetTotal),
            ),
            _SummaryTile(
              label: 'Wall cabinets',
              value: formatMoney(summary.wallCabinetTotal),
            ),
            if (summary.tallCabinetTotal > 0)
              _SummaryTile(
                label: 'Tall cabinets',
                value: formatMoney(summary.tallCabinetTotal),
              ),
            if (summary.benchtopTotal > 0)
              _SummaryTile(
                label: 'Benchtop: ${summary.benchtopMaterial} '
                    '(${summary.benchtopLinearMetres.toStringAsFixed(2)} m)',
                value: formatMoney(summary.benchtopTotal),
              ),
            _SummaryTile(
              label: 'Finish (${summary.styleName})',
              value: '×${summary.materialMultiplier}',
            ),
            _SummaryTile(
              label: 'Installation (${summary.labourModules} units)',
              value: formatMoney(summary.labourTotal),
            ),
            if (summary.obstacleAllowance != 0)
              _SummaryTile(
                label: 'Window and door adjustment',
                value: formatMoney(summary.obstacleAllowance),
              ),
            _SummaryTile(
              label: '${SalesConfig.taxLabel} ($taxPercent%)',
              value: formatMoney(summary.gst),
            ),
            const Divider(color: AppTheme.border),
            _SummaryTile(
              label: 'Estimated total',
              value: formatMoney(summary.totalPrice),
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimateBar(CPQSummary summary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
          Expanded(
            child: _priceVisible
                ? InkWell(
                    onTap: _showBOQSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween:
                              Tween<double>(begin: 0, end: summary.totalPrice),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          builder: (context, val, _) => Text(
                            formatMoney(val),
                            style: context.textTheme.titleLarge
                                ?.copyWith(color: context.colors.onSurface),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary.totalPrice > 0
                              ? 'Estimate · ${cabinetCountLabel(_cabinetCount)} · Details'
                              : 'Add cabinets to see an estimate',
                          style: context.textTheme.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      // Flexible so a large system font size can't overflow.
                      Flexible(
                        child: TextButton.icon(
                          onPressed: () => setState(() => _priceVisible = true),
                          icon: const Icon(
                            Icons.visibility_outlined,
                            size: 20,
                          ),
                          label: const Text(
                            'Show price',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (_priceVisible)
            IconButton(
              tooltip: 'Hide price',
              onPressed: () => setState(() => _priceVisible = false),
              icon: const Icon(
                Icons.visibility_off_outlined,
                color: AppTheme.textSecondary,
                size: 20,
              ),
            ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _sceneLoaded && !_rendering ? _openClosingModal : null,
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Quote'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _cpqSummary;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_clientName.isEmpty ? '3D design' : _clientName),
        actions: [
          IconButton(
            tooltip: 'Look: doors, backsplash, decor, room and light',
            onPressed: _sceneLoaded && !_rendering ? _showLookSheet : null,
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: 'Take pictures of this design',
            onPressed: _sceneLoaded && !_rendering ? _takePictures : null,
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          IconButton(
            tooltip: _controlsHidden ? 'Show controls' : 'Full view',
            onPressed: () => setState(() => _controlsHidden = !_controlsHidden),
            icon: Icon(
              _controlsHidden
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          // ── 3D view ─────────────────────────────────────────────────────
          _scene.buildView(),

          if (_controlsHidden)
            Positioned(
              right: 14,
              bottom: 14,
              child: PointerShield(
                child: FloatingActionButton.extended(
                  onPressed: () => setState(() => _controlsHidden = false),
                  backgroundColor: AppTheme.surface,
                  foregroundColor: AppTheme.textPrimary,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Show controls'),
                ),
              ),
            )
          else ...[
            // ── Style ────────────────────────────────────────────────────────
            Positioned(
              top: 12,
              left: 14,
              right: 14,
              // Only as wide as the pills, so the 3D view beside them stays
              // draggable in the browser.
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PointerShield(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
              ),
            ),

            // ── Kitchen / Room / House (rooms read off a floor plan) ─────
            if (_floorPlan != null)
              Positioned(
                top: 66,
                left: 14,
                child: PointerShield(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'kitchen', label: Text('Kitchen')),
                      ButtonSegment(value: 'room', label: Text('Room')),
                      ButtonSegment(value: 'house', label: Text('House')),
                    ],
                    selected: {_roomView},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _setRoomView(s.first),
                    style: SegmentedButton.styleFrom(
                      backgroundColor: AppTheme.surface,
                      selectedBackgroundColor: AppTheme.accent,
                      selectedForegroundColor: Colors.white,
                    ),
                  ),
                ),
              ),

            // ── Layouts / Edit panel + estimate ───────────────────────────
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: PointerShield(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_editing)
                      _EditPanel(
                        selectedLabel: _selectedLabel,
                        selectedMovable: _selectedMovable,
                        hasCabinets: _placedCabinets.isNotEmpty,
                        onAdd: _spawnCabinet,
                        onSelectAdjacent: _selectAdjacent,
                        onMove: _nudgeSelected,
                        onRemoveSelected: _removeSelected,
                        onClearAll: _clearLayout,
                        onAppliances: _showApplianceSheet,
                        onBenchtop: _showBenchtopSheet,
                        benchtopName: _benchtopMaterial == null
                            ? null
                            : _catalog.benchtopOptions[_benchtopMaterial]?.name,
                        modules: _catalog.cabinetModules,
                        kindOf: _catalog.kindOf,
                        onDone: () => _setEditing(false),
                      )
                    else
                      _LayoutVariantBar(
                        variants: _variants,
                        activeKey: _activeVariantKey,
                        onSelect: _selectVariant,
                        onEdit: () => _setEditing(true),
                      ),
                    const SizedBox(height: 8),
                    _buildEstimateBar(summary),
                  ],
                ),
              ),
            ),
          ],

          // ── Loading overlay ─────────────────────────────────────────────
          if (!_sceneLoaded)
            ColoredBox(
              color: AppTheme.bg,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.accent),
                    SizedBox(height: 16),
                    Text(
                      'Loading 3D view…',
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: context.colors.onSurfaceVariant),
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

    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        // Visual stays compact; the tap area is 48dp tall.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
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
                  ? [
                      BoxShadow(
                          color: AppTheme.accent.withOpacity(0.2),
                          blurRadius: 8)
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
                  style: context.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? context.colors.onPrimary
                          : context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared look for the floating panels over the 3D view.
class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}

/// Layouts mode: the A / B / C switcher the salesperson flips through with
/// the client, and the way into Edit mode.
class _LayoutVariantBar extends StatelessWidget {
  final List<LayoutVariant> variants;
  final String? activeKey;
  final ValueChanged<LayoutVariant> onSelect;
  final VoidCallback onEdit;

  const _LayoutVariantBar({
    required this.variants,
    required this.activeKey,
    required this.onSelect,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final sample = variants.any((v) => v.usesPlaceholderCatalog);
    final title = sample ? 'Sample layouts' : 'Layouts';
    final note =
        variants.isNotEmpty && activeKey == null ? ' · your changes' : '';
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: title,
                    style: context.textTheme.labelLarge
                        ?.copyWith(color: context.colors.onSurface),
                    children: [
                      TextSpan(
                        text: note,
                        style: context.textTheme.labelSmall
                            ?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  minimumSize: const Size(48, 44),
                ),
              ),
            ],
          ),
          if (variants.isNotEmpty)
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

/// Edit mode: add cabinets, remove the selected one, or clear everything.
class _EditPanel extends StatelessWidget {
  final String? selectedLabel;
  final bool selectedMovable;
  final bool hasCabinets;
  final void Function(String type) onAdd;
  final ValueChanged<int> onSelectAdjacent;
  final ValueChanged<int> onMove;
  final VoidCallback onRemoveSelected;
  final VoidCallback onClearAll;
  final VoidCallback onAppliances;
  final VoidCallback onBenchtop;

  /// The modules offered in the tray, from the catalogue.
  final List<CatalogModule> modules;

  /// How the 3D view draws a module type (picks its icon).
  final String Function(String type) kindOf;

  /// The chosen benchtop's name, or null for none.
  final String? benchtopName;
  final VoidCallback onDone;

  const _EditPanel({
    required this.selectedLabel,
    required this.selectedMovable,
    required this.hasCabinets,
    required this.onAdd,
    required this.onSelectAdjacent,
    required this.onMove,
    required this.onRemoveSelected,
    required this.onClearAll,
    required this.onAppliances,
    required this.onBenchtop,
    required this.benchtopName,
    required this.modules,
    required this.kindOf,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedLabel;
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_outlined, size: 16, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                'Edit cabinets',
                style: context.textTheme.labelLarge
                    ?.copyWith(color: context.colors.onSurface),
              ),
              const Spacer(),
              TextButton(
                onPressed: onDone,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  minimumSize: const Size(48, 44),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
          Text(
            switch ((selected, selectedMovable)) {
              (null, _) => 'Tap a cabinet in the view, or use Pick.',
              (_, true) => '$selected selected. Drag it, or use Move.',
              (_, false) =>
                "$selected selected. Corner-wall cabinets can't be moved yet.",
            },
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          if (hasCabinets) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ControlGroup(
                  label: 'Pick',
                  children: [
                    IconButton.outlined(
                      tooltip: 'Previous cabinet',
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => onSelectAdjacent(-1),
                    ),
                    IconButton.outlined(
                      tooltip: 'Next cabinet',
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => onSelectAdjacent(1),
                    ),
                  ],
                ),
                if (selected != null && selectedMovable)
                  _ControlGroup(
                    label: 'Move',
                    children: [
                      NudgeButtons(
                        vertical: false,
                        onNudge: (dx, _) => onMove(dx),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < modules.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _JoineryModuleButton(
                    type: modules[i].type,
                    label: modules[i].label,
                    dims: _moduleDims(modules[i], kindOf(modules[i].type)),
                    icon: _moduleIcon(kindOf(modules[i].type)),
                    onAdd: () => onAdd(modules[i].type),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onAppliances,
                icon: const Icon(Icons.kitchen_outlined, size: 18),
                label: const Text('Appliances'),
              ),
              OutlinedButton.icon(
                onPressed: onBenchtop,
                icon: const Icon(Icons.countertops_outlined, size: 18),
                label: Text(benchtopName == null
                    ? 'Benchtop'
                    : 'Benchtop: $benchtopName'),
              ),
            ],
          ),
          if (selected != null || hasCabinets) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (selected != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRemoveSelected,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(
                        'Remove $selected',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: AppTheme.danger),
                        minimumSize: const Size(48, 44),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (hasCabinets) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onClearAll,
                    icon: const Icon(Icons.layers_clear_outlined, size: 18),
                    label: const Text('Clear all'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      minimumSize: const Size(48, 44),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small caption ("Pick", "Move") in front of a few icon buttons.
class _ControlGroup extends StatelessWidget {
  const _ControlGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.textTheme.labelMedium
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          child,
        ],
      ],
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
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        // Visual stays compact; the tap area is 48dp tall.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppTheme.accent : AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: selected ? AppTheme.accent : AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${variant.key} · ${variant.name}',
                  style: context.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? context.colors.onPrimary
                          : context.colors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  variant.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? context.colors.onPrimary
                          : context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
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
            style: context.textTheme.labelSmall?.copyWith(
                color: isBold
                    ? context.colors.onSurface
                    : context.colors.onSurfaceVariant),
          ),
          Text(
            value,
            style: context.textTheme.labelLarge?.copyWith(
                color:
                    isBold ? context.colors.primary : context.colors.onSurface),
          ),
        ],
      ),
    );
  }
}

/// The size worth showing on a tray button: the height of full-height units,
/// the width of everything else.
String _moduleDims(CatalogModule m, String kind) {
  final tall = kind == 'tall' || kind == 'oven' || kind == 'fridge';
  return '${(tall ? m.heightMm : m.widthMm).round()} mm';
}

IconData _moduleIcon(String kind) => switch (kind) {
      'wall' => Icons.table_rows_outlined,
      'tall' => Icons.view_sidebar_outlined,
      'corner' => Icons.turn_right_outlined,
      'drawer' => Icons.table_chart_outlined,
      'filler' => Icons.horizontal_rule_rounded,
      _ => Icons.view_agenda_outlined,
    };

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
                  style: context.textTheme.labelSmall
                      ?.copyWith(color: context.colors.onSurface),
                ),
                Text(
                  dims,
                  style: context.textTheme.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
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
