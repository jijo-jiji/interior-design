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
import '../../layout/width_check.dart';
import '../models/cpq_engine.dart';
import '../models/cabinet_choices.dart';
import '../models/scene_look.dart';
import '../scene/finish_textures.dart';
import '../scene/scene_bridge.dart';
import '../../trace/utils/wall_photo.dart';
import '../utils/design_pictures.dart';
import '../utils/proposal_delivery.dart';
import '../widgets/cabinet_card.dart';
import '../widgets/wall_card.dart';
import '../models/wall_work.dart';
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
  ({
    int revision,
    List<String> images,
    RenderEngine engine,
    RenderStats? stats,
  })? _rendered;

  /// What the page said about the render it last finished: the engine that
  /// made it, and whether it fell back on another for want of the device.
  ({RenderEngine? engine, bool fellBack, RenderStats? stats}) _lastRender =
      (engine: null, fellBack: false, stats: null);

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

  /// The cabinet whose card is open (a double tap on it in the 3D view).
  String? _openId;

  /// A unit being added: what it is, its size and where it would go (the
  /// "Add" card is open and the 3D view shows it see-through).
  _Adding? _adding;

  /// The wall card is open (a double tap on the wall, or Edit, Wall); the
  /// door or window being changed on it; where the wall was tapped (a new
  /// opening goes there).
  bool _wallOpen = false;
  int? _wallSelected;
  double? _wallTapMm;
  WallTab _wallTab = WallTab.openings;

  /// Undo and redo: the cabinets (and the layout they came from) before each
  /// change to them.
  final List<_Cabinets> _undo = [];
  final List<_Cabinets> _redo = [];

  /// The 3D view and the panel over its bottom, to frame a cabinet in the
  /// part of the view the card leaves.
  final _viewKey = GlobalKey();
  final _panelKey = GlobalKey();

  /// Full view hides every control so the client sees the whole design.
  bool _controlsHidden = false;

  final List<Map<String, dynamic>> _placedCabinets = [];
  /// The main wall's doors and windows; those to be made (the wall card)
  /// carry a `work` key and are priced.
  late List<Map<String, dynamic>> _obstacles;

  /// The wall's finish from the wall card ({kind, area_m2, colour}), or null.
  Map<String, dynamic>? _wallFinish;

  /// The payload the design came with, for working the layouts out again
  /// when a door or window is added to the wall.
  Map<String, dynamic>? _payload;
  late final Map<String, dynamic> _wallData;

  /// The floor plan this room was read from, for the Room and House views
  /// (see FloorplanSizesScreen); null for rooms measured another way.
  Map<String, dynamic>? _floorPlan;

  /// How the wall was measured on the photo (camera route): kept with the
  /// design so it can be checked against a tape later.
  Map<String, dynamic>? _capture;

  /// Where that wall photo is on this phone, and whether the client let the
  /// office keep it (asked on the quote sheet).
  String? _wallPhotoPath;
  bool _keepWallPhoto = true;

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

  /// For each layout, by key: what would change if the wall were a little
  /// narrower or wider. Only when the wall's size came from the photo; a
  /// typed measurement needs no such check.
  Map<String, WidthSensitivity> _widthChecks = const {};

  /// Generates the A/B/C layouts for [room], and checks each against the
  /// photo's measuring error if the size came from the photo.
  void _layOut(KitchenRoom room) {
    final generator = KitchenLayoutGenerator.forCatalog(_catalog);
    _variants = generator.generateAll(room);
    final fromPhoto =
        const {'worktop', 'door', 'assumed'}.contains(_capture?['size_from']);
    _widthChecks = {
      if (fromPhoto)
        for (final v in _variants)
          if (widthSensitivity(generator, room, v.tier) case final s?) v.key: s,
    };
  }

  @override
  void initState() {
    super.initState();

    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(widget.jsonPayload) as Map<String, dynamic>;
      _wallData = parsed['wall'] as Map<String, dynamic>? ?? {};
      _obstacles = [
        for (final o in parsed['obstacles'] as List<dynamic>? ?? const [])
          Map<String, dynamic>.from(o as Map),
      ];
      final finish = parsed['wall_finish'];
      _wallFinish = finish is Map ? Map<String, dynamic>.from(finish) : null;
      _payload = parsed;
      _floorPlan = parsed['floor_plan'] as Map<String, dynamic>?;
      _capture = parsed['capture'] as Map<String, dynamic>?;
      _wallPhotoPath = parsed['wall_photo_path'] as String?;
      _keepWallPhoto = parsed['keep_wall_photo'] as bool? ?? true;
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
        _layOut(KitchenRoom.fromPayload({...parsed, 'obstacles': _obstacles}));
        final initial = _variants.where(
            (v) => v.tier == LayoutTier.balanced && v.modules.isNotEmpty);
        if (_placedCabinets.isEmpty && initial.isNotEmpty) {
          _activeVariantKey = initial.first.key;
          _placedCabinets.addAll(initial.first.toPlacedCabinets());
        }
      } catch (_) {
        _variants = const [];
        _widthChecks = const {};
      }
    }

    _scene = SceneBridge(onMessage: _onJsMessage, onLoaded: _injectScene);

    _loadHtml();
  }

  Future<void> _loadHtml() async {
    final threeJs = await rootBundle.loadString('assets/3d/three.min.js');
    var orbitJs = await rootBundle.loadString('assets/3d/OrbitControls.js');
    final pathTracerJs =
        await rootBundle.loadString('assets/3d/pathtracer.min.js');
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
      '<script>$threeJs</script>\n<script>$orbitJs</script>\n'
      '<script>$pathTracerJs</script>\n</head>',
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
    // The wall as it is now (a door or a finish may have been added since
    // the design was opened).
    await _pushWallWork();
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
      if (_wallFinish != null) 'wall_finish': _wallFinish,
      if (_floorPlan != null) 'floor_plan': _floorPlan,
      if (_capture != null) 'capture': _capture,
      if (_capture != null) 'keep_wall_photo': _keepWallPhoto,
      // On this phone only: lets a draft send its photo later.
      if (_wallPhotoPath != null) 'wall_photo_path': _wallPhotoPath,
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

  // ── The wall card ──────────────────────────────────────────────────────────

  WallWorkModel get _wallModel => WallWorkModel(
        catalog: _catalog,
        wall: _wallData,
        obstacles: _obstacles,
        cabinets: _placedCabinets,
      );

  /// The colours each finish comes in (the first is the one it starts with).
  static const _wallColours = {
    'paint': [
      ('Warm white', '#efebe4'),
      ('Greige', '#d9d2c7'),
      ('Sage', '#c9d3c3'),
      ('Clay', '#d8bfa8'),
    ],
    'tiles': [
      ('White', '#f4f2ee'),
      ('Grey', '#cfcfcc'),
      ('Sage', '#b9c7b5'),
      ('Sand', '#e2d3bd'),
    ],
    'panels': [
      ('Oak', '#c9a77e'),
      ('Walnut', '#8a6a52'),
      ('White', '#eeeae3'),
      ('Charcoal', '#5a5a5a'),
    ],
  };

  static String _finishName(String kind) => switch (kind) {
        'paint' => 'Paint',
        'tiles' => 'Tiles',
        'panels' => 'Panels',
        _ => kind,
      };

  /// A double tap on the wall (or on one of its doors or windows), or Edit,
  /// Wall: its card opens and the camera faces the wall.
  void _openWall({int? opening, double? xMm}) {
    if (_adding != null) _scene.runJavaScript('clearPreview()');
    final hadCabinet = _openId != null;
    setState(() {
      _adding = null;
      _openId = null;
      _wallOpen = true;
      _wallSelected =
          opening != null && opening >= 0 && opening < _obstacles.length
              ? opening
              : null;
      _wallTapMm = xMm;
    });
    if (hadCabinet) _scene.runJavaScript('deselectCabinet()');
    HapticFeedback.selectionClick();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_wallOpen) return;
      _scene.runJavaScript('focusWall(${_cardInset().toStringAsFixed(3)}); '
          'highlightOpening(${jsonEncode(_wallSelected)})');
    });
  }

  void _closeWall() {
    setState(() {
      _wallOpen = false;
      _wallSelected = null;
    });
    _scene.runJavaScript('highlightOpening(null); unfocusCabinet()');
  }

  /// The wall as the app has it, to the 3D page.
  Future<void> _pushWallWork() => _scene.runJavaScript('setWallWork(${jsonEncode(
      jsonEncode({'obstacles': _obstacles, 'wall_finish': _wallFinish}))})');

  /// The A/B/C layouts again, for the wall as it is now (a new door must not
  /// get cabinets in front of it). The current one stays chosen only if it
  /// still comes out the same.
  void _regenerateVariants() {
    final payload = _payload;
    if (payload == null) return;
    try {
      _layOut(KitchenRoom.fromPayload({...payload, 'obstacles': _obstacles}));
    } catch (_) {
      _variants = const [];
      _widthChecks = const {};
    }
    final active = _variants.where((v) => v.key == _activeVariantKey);
    if (active.isEmpty ||
        jsonEncode(active.first.toPlacedCabinets()) !=
            jsonEncode(_placedCabinets)) {
      _activeVariantKey = null;
    }
  }

  /// A change made on the wall card: its openings and/or its finish (whose
  /// area follows the openings). Undoable.
  void _changeWall(List<Map<String, dynamic>> obstacles,
      {Map<String, dynamic>? finish, bool finishChanged = false, int? select}) {
    _remember();
    final nextFinish = finishChanged ? finish : _wallFinish;
    setState(() {
      final openingsChanged = jsonEncode(obstacles) != jsonEncode(_obstacles);
      _obstacles = obstacles;
      _wallFinish = nextFinish == null
          ? null
          : _wallModel.finish(nextFinish['kind'] as String,
              colour: nextFinish['colour'] as String?);
      if (openingsChanged) _regenerateVariants();
      _wallSelected = select;
    });
    _pushWallWork().then((_) =>
        _scene.runJavaScript('highlightOpening(${jsonEncode(_wallSelected)})'));
    HapticFeedback.lightImpact();
    _scheduleSave();
  }

  /// What a wall change would do to the total, when the price is shown.
  String? _wallPriceChange(List<Map<String, dynamic>> obstacles,
      {Map<String, dynamic>? finish, bool finishChanged = false}) {
    if (!_priceVisible) return null;
    final model = WallWorkModel(
        catalog: _catalog,
        wall: _wallData,
        obstacles: obstacles,
        cabinets: _placedCabinets);
    final next = finishChanged ? finish : _wallFinish;
    return _priceChange(_placedCabinets,
        obstacles: obstacles,
        finishChanged: true,
        wallFinish: next == null
            ? null
            : model.finish(next['kind'] as String,
                colour: next['colour'] as String?));
  }

  Widget _buildWallCard() {
    final model = _wallModel;
    final kind = _wallFinish?['kind'] as String?;
    final colour = _wallFinish?['colour'] as String?;
    final selected = _wallSelected;
    final open = selected == null ? null : _obstacles[selected];
    final summary = _cpqSummary;
    String mm(Object? v) => '${(v as num? ?? 0).round()}';

    return WallCard(
      title: 'Main wall',
      tab: _wallTab,
      onTab: (t) => setState(() => _wallTab = t),
      size: '${mm(_wallData['width_mm'])} × ${mm(_wallData['height_mm'])} mm'
          ' · ${model.finishAreaM2.toStringAsFixed(2)} m² of wall',
      price: _priceVisible && summary.wallWorkTotal != 0
          ? formatMoney(summary.wallWorkTotal)
          : null,
      samplePrices: _catalog.wallWork.isPlaceholder,
      finishes: [
        WallOption<String?>(null, 'As it is',
            selected: kind == null,
            price: kind == null
                ? null
                : _wallPriceChange(_obstacles, finishChanged: true)),
        for (final k in _catalog.wallWork.finishes.keys)
          WallOption<String?>(k, _finishName(k),
              selected: kind == k,
              price: kind == k
                  ? null
                  : _wallPriceChange(_obstacles,
                      finish: {'kind': k}, finishChanged: true)),
      ],
      colours: [
        if (kind != null)
          for (final (name, hex) in _wallColours[kind] ?? const <(String, String)>[])
            WallOption<String>(hex, name,
                selected: (colour ?? _wallColours[kind]!.first.$2) == hex,
                colour: Color(int.parse('ff${hex.substring(1)}', radix: 16))),
      ],
      openings: [
        for (final o in _obstacles)
          WallOpeningItem(
            name: WallWorkModel.nameOf(o),
            label: '${WallWorkModel.nameOf(o)} ${mm(o['width_mm'])}',
            detail: '${WallWorkModel.nameOf(o)} · ${WallWorkModel.sizeOf(o)}'
                ' · ${WallWorkModel.isNew(o) ? 'to be made' : 'already there, not priced'}',
            isNew: WallWorkModel.isNew(o),
          ),
      ],
      selected: selected,
      widths: [
        if (open != null && WallWorkModel.isNew(open))
          for (final w in model.widthsFor(selected!))
            WallOption<double>(w.widthMm, '${w.widthMm.round()}',
                selected: w.current, problem: w.problem),
      ],
      adds: [
        for (final k in model.kinds)
          WallOption<String>(k, WallWorkModel.addName(k),
              problem: model.whyNot(k),
              price: _priceVisible
                  ? '+${formatMoney(_catalog.wallWork.openings[k]!.price)}'
                  : null),
      ],
      onFinish: (k) => _changeWall(_obstacles,
          finish: k == null
              ? null
              : {'kind': k, 'colour': _wallColours[k]?.first.$2},
          finishChanged: true,
          select: _wallSelected),
      onColour: (hex) => _changeWall(_obstacles,
          finish: {'kind': kind, 'colour': hex},
          finishChanged: true,
          select: _wallSelected),
      onSelect: (i) {
        setState(() => _wallSelected = i);
        _scene.runJavaScript('highlightOpening(${jsonEncode(i)})');
      },
      onWidth: (w) {
        final next = model.resize(selected!, w);
        if (next != null) _changeWall(next, select: selected);
      },
      onMove: (dx) {
        final next = model.move(selected!, dx * 50.0);
        if (next == null) {
          HapticFeedback.heavyImpact();
          return;
        }
        _changeWall(next, select: selected);
      },
      onRemove: () => _changeWall(model.remove(selected!)),
      onAdd: (k) {
        final next = model.add(k, nearMm: _wallTapMm);
        if (next == null) return;
        _changeWall(next, select: next.length - 1);
      },
      onClose: _closeWall,
    );
  }

  // ── Adding a unit: see it first ────────────────────────────────────────────

  /// The tray or the appliance list: the unit's card opens first, showing
  /// what it is, its sizes and where it can go, and the 3D view shows it
  /// there; nothing is added until Place.
  void _openAdding(String type) {
    final choices = _choices;
    final sizes = choices.addChoices(type);
    if (sizes.isEmpty) return;
    final choice = sizes.firstWhere((c) => c.current && c.fits,
        orElse: () => sizes.firstWhere((c) => c.fits, orElse: () => sizes.firstWhere((c) => c.current)));
    final places = choices.placementsFor(choice, near: _selectedId ?? _openId);
    if (_wallOpen) _scene.runJavaScript('highlightOpening(null)');
    setState(() {
      _openId = null;
      _wallOpen = false;
      _wallSelected = null;
      _adding = _Adding(type: type, choice: choice, place: places.firstOrNull);
    });
    HapticFeedback.selectionClick();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showAdding());
  }

  /// The see-through unit where it would go, and the camera on it.
  void _showAdding() {
    final adding = _adding;
    if (adding == null || !mounted) return;
    final place = adding.place;
    if (place == null) {
      _scene.runJavaScript('clearPreview()');
      return;
    }
    final record = _choices.recordFor(adding.choice, place, '__preview__');
    _scene.runJavaScript('previewCabinet(${jsonEncode(jsonEncode(record))}, '
        '${_cardInset().toStringAsFixed(3)})');
  }

  void _addingSize(CabinetChoice choice) => _refreshAdding(choice);

  /// After a size change, or the cabinets changing underneath the Add card
  /// (undo, a layout, a move): the free spaces again, staying in the same
  /// one if it is still there.
  void _refreshAdding([CabinetChoice? choice]) {
    final adding = _adding;
    if (adding == null || !mounted) return;
    final next = choice ?? adding.choice;
    final places = _choices.placementsFor(next, near: _selectedId);
    final same = places.where((p) => p == adding.place).firstOrNull;
    setState(() => _adding = _Adding(
        type: adding.type, choice: next, place: same ?? places.firstOrNull));
    _showAdding();
  }

  void _addingWhere(Placement place) {
    final adding = _adding;
    if (adding == null) return;
    setState(() => _adding =
        _Adding(type: adding.type, choice: adding.choice, place: place));
    _showAdding();
  }

  /// Place: added for real, and its card opens so it can be changed.
  void _placeAdding() {
    final adding = _adding;
    final place = adding?.place;
    if (adding == null || place == null) return;
    final id = 'C-${DateTime.now().microsecondsSinceEpoch}';
    final next = _choices.add(adding.choice, place, id);
    _remember();
    setState(() {
      _adding = null;
      _placedCabinets
        ..clear()
        ..addAll(next);
      _activeVariantKey = null; // now the salesperson's own layout
    });
    _scene.runJavaScript('clearPreview()');
    HapticFeedback.lightImpact();
    _scheduleSave();
    _pushCabinetsToScene().then((_) {
      if (mounted) _openCard(id);
    });
  }

  void _cancelAdding() {
    setState(() => _adding = null);
    _scene.runJavaScript('clearPreview(); unfocusCabinet()');
  }

  /// How much of the 3D view (0 to 0.7) the panel over its bottom covers.
  double _cardInset() {
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    final panel = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (view == null || panel == null || !view.hasSize || !panel.hasSize) {
      return 0.45;
    }
    final viewTop = view.localToGlobal(Offset.zero).dy;
    final panelTop = panel.localToGlobal(Offset.zero).dy;
    return ((viewTop + view.size.height - panelTop) / view.size.height)
        .clamp(0.0, 0.7);
  }

  Widget _buildAddingCard(_Adding adding) {
    final choices = _choices;
    final sizes = choices.addChoices(adding.type);
    final place = adding.place;
    final preview = place == null
        ? null
        : choices.recordFor(adding.choice, place, '__preview__');
    String? change(CabinetChoice c) {
      if (!_priceVisible || !c.fits) return null;
      final at = choices.placementsFor(c).firstOrNull;
      return at == null ? null : _priceChange(choices.add(c, at, '__preview__'));
    }

    return AddCabinetCard(
      name: adding.choice.label,
      description: choices.describe(preview ??
          {
            'kind': adding.choice.kind,
            'width_mm': adding.choice.widthMm,
            'cabinet_type': adding.choice.type,
          }),
      size: choices.sizeOf({
        'width_mm': adding.choice.widthMm,
        'height_mm': adding.choice.heightMm,
        'depth_mm': adding.choice.depthMm,
      }),
      priceChange: _priceVisible && place != null
          ? _priceChange(choices.add(adding.choice, place, '__preview__'))
          : null,
      sizes: [
        for (final c in sizes)
          CardOption(
            CabinetChoice(
              kind: c.kind,
              type: c.type,
              label: c.label,
              widthMm: c.widthMm,
              heightMm: c.heightMm,
              depthMm: c.depthMm,
              mountMm: c.mountMm,
              current: c.type == adding.choice.type,
              problem: c.problem,
            ),
            priceChange: c.type == adding.choice.type ? null : change(c),
          ),
      ],
      places: choices.placementsFor(adding.choice, near: _selectedId),
      place: place,
      onSize: _addingSize,
      onWhere: _addingWhere,
      onPlace: _placeAdding,
      onCancel: _cancelAdding,
    );
  }

  /// Replaces every cabinet in the 3D scene with [_placedCabinets].
  Future<void> _pushCabinetsToScene() {
    // Double-encoded: the inner JSON becomes a safe JS string literal.
    return _scene.runJavaScript(
        'replaceCabinets(${jsonEncode(jsonEncode(_placedCabinets))})');
  }

  // ── Undo / redo ────────────────────────────────────────────────────────────

  _Cabinets _snapshot() => (
        cabinets: [for (final c in _placedCabinets) Map<String, dynamic>.of(c)],
        variant: _activeVariantKey,
        obstacles: [for (final o in _obstacles) Map<String, dynamic>.of(o)],
        wallFinish: _wallFinish == null ? null : Map.of(_wallFinish!),
      );

  /// Called before the cabinets change, so the change can be undone.
  void _remember() {
    _undo.add(_snapshot());
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoRedo({required bool undo}) {
    final from = undo ? _undo : _redo;
    if (from.isEmpty) return;
    (undo ? _redo : _undo).add(_snapshot());
    final back = from.removeLast();
    final wallChanged = jsonEncode(back.obstacles) != jsonEncode(_obstacles) ||
        jsonEncode(back.wallFinish) != jsonEncode(_wallFinish);
    setState(() {
      _placedCabinets
        ..clear()
        ..addAll(back.cabinets);
      _obstacles = back.obstacles;
      _wallFinish = back.wallFinish;
      if (wallChanged) _regenerateVariants();
      _activeVariantKey = back.variant;
      if (_wallSelected != null && _wallSelected! >= _obstacles.length) {
        _wallSelected = null;
      }
      if (_openId != null && _cabinet(_openId!) == null) _openId = null;
      _selectedId = _openId;
      _selectedLabel = _openId == null ? null : _choices.nameOf(_cabinet(_openId!)!);
    });
    if (wallChanged) _pushWallWork();
    _pushCabinetsToScene().then((_) {
      if (_openId != null) {
        _focusOpen();
      } else if (!_wallOpen) {
        _scene.runJavaScript('unfocusCabinet()');
      }
    });
    HapticFeedback.selectionClick();
    _scheduleSave();
    _refreshAdding();
  }

  // ── The cabinet card ───────────────────────────────────────────────────────

  Map<String, dynamic>? _cabinet(String id) {
    for (final c in _placedCabinets) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  CabinetChoices get _choices => CabinetChoices(
        catalog: _catalog,
        cabinets: _placedCabinets,
        wall: _wallData,
        obstacles: _obstacles,
      );

  /// A double tap on a cabinet: its card opens and the camera goes to it.
  void _openCard(String id) {
    final record = _cabinet(id);
    if (record == null) return;
    if (_adding != null) _scene.runJavaScript('clearPreview()');
    if (_wallOpen) _scene.runJavaScript('highlightOpening(null)');
    setState(() {
      _adding = null;
      _wallOpen = false;
      _wallSelected = null;
      _openId = id;
      _selectedId = id;
      _selectedLabel = _choices.nameOf(record);
      _selectedMovable = record['run'] != 'return';
    });
    HapticFeedback.selectionClick();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusOpen());
  }

  /// Takes the camera to the open cabinet, framed in the part of the view
  /// the card doesn't cover.
  void _focusOpen() {
    final id = _openId;
    if (id == null || !mounted) return;
    final inset = _cardInset();
    _scene.runJavaScript(
        'focusCabinet(${jsonEncode(id)}, ${inset.toStringAsFixed(3)})');
  }

  void _closeCard() {
    setState(() {
      _openId = null;
      _selectedId = null;
      _selectedLabel = null;
    });
    _scene.runJavaScript('deselectCabinet(); unfocusCabinet()');
  }

  /// Turns the open cabinet into [choice], in its place.
  void _pickChoice(CabinetChoice choice) {
    final id = _openId;
    if (id == null) return;
    final next = _choices.swap(id, choice);
    if (next == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(choice.problem ?? "That doesn't fit here.")));
      return;
    }
    _remember();
    setState(() {
      _placedCabinets
        ..clear()
        ..addAll(next);
      _activeVariantKey = null; // now the salesperson's own layout
      _selectedLabel = choice.label;
    });
    _pushCabinetsToScene().then((_) => _focusOpen());
    HapticFeedback.lightImpact();
    _scheduleSave();
  }

  /// "+RM 80", "−RM 40" or "same price": what [next] does to the total.
  /// Null while the price is hidden from the client.
  String? _priceChange(List<Map<String, dynamic>>? next,
      {List<Map<String, dynamic>>? obstacles,
      Map<String, dynamic>? wallFinish,
      bool finishChanged = false}) {
    if (!_priceVisible || next == null) return null;
    final then = CPQEngine.calculate(
      placedCabinets: next,
      obstacles: obstacles ?? _obstacles,
      styleArchetype: _currentStyle,
      benchtopMaterial: _benchtopMaterial,
      catalog: _catalog,
      wallFinish: finishChanged ? wallFinish : _wallFinish,
    ).totalPrice;
    final change = (then - _cpqSummary.totalPrice).round();
    if (change == 0) return 'same price';
    return change > 0 ? '+${formatMoney(change)}' : '\u2212${formatMoney(-change)}';
  }

  Widget _buildCabinetCard(Map<String, dynamic> record) {
    final choices = _choices;
    final id = record['id'] as String;
    List<CardOption> options(List<CabinetChoice> list) => [
          for (final c in list)
            CardOption(c,
                priceChange:
                    c.current || !c.fits ? null : _priceChange(choices.swap(id, c))),
        ];
    final type = record['cabinet_type'] as String? ?? '';
    final width = (record['width_mm'] as num?)?.toDouble();
    return CabinetCard(
      name: choices.nameOf(record),
      description: choices.describe(record),
      size: choices.sizeOf(record),
      price: _priceVisible
          ? formatMoney(_catalog.unitPrice(type, width) *
              _cpqSummary.materialMultiplier)
          : null,
      sizes: options(choices.sizesFor(id)),
      types: options(choices.typesFor(id)),
      movable: record['run'] != 'return',
      onPick: _pickChoice,
      onMove: (dx) {
        _scene.runJavaScript('nudgeSelectedCabinet(${dx * 50}, true)');
        HapticFeedback.selectionClick();
      },
      onRemove: () {
        _scene.runJavaScript('removeSelectedCabinet()');
        HapticFeedback.lightImpact();
      },
      onClose: _closeCard,
    );
  }

  void _selectVariant(LayoutVariant variant) {
    if (variant.key != _activeVariantKey) _remember();
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
    _refreshAdding();
  }

  void _clearLayout() {
    _remember();
    final previous = List<Map<String, dynamic>>.from(_placedCabinets);
    final previousVariant = _activeVariantKey;
    setState(() {
      _activeVariantKey = null;
      _placedCabinets.clear();
      _selectedId = null;
      _selectedLabel = null;
    });
    _pushCabinetsToScene();
    _refreshAdding();
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
                _refreshAdding();
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
    if (!editing && _adding != null) _scene.runJavaScript('clearPreview()');
    setState(() {
      _editing = editing;
      if (!editing) {
        _adding = null;
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
          if (data['rendered'] == true) {
            _lastRender = (
              engine: switch (data['engine']) {
                'path' => RenderEngine.path,
                'sky' => RenderEngine.sky,
                _ => null,
              },
              fellBack: data['fell_back'] == true,
              stats: RenderStats.fromJson(data['stats']),
            );
          }
          _pictureRequests
              .remove(data['request_id'] as String? ?? 'app')
              ?.complete([
            for (final image in (data['images'] as List? ?? const []))
              if (image is String) image,
          ]);
        case 'render_progress':
          _renderProgress.value = (data['fraction'] as num?)?.toDouble();
        case 'cabinet_placed':
          _remember();
          setState(() {
            _placedCabinets.add(data);
            _activeVariantKey = null; // now the salesperson's own layout
          });
          _scheduleSave();
          _refreshAdding();
        case 'cabinet_removed':
          _remember();
          if (_openId != null && _openId == data['id']) {
            _openId = null;
            _scene.runJavaScript('unfocusCabinet()');
          }
          setState(() {
            _placedCabinets.removeWhere((c) => c['id'] == data['id']);
            _activeVariantKey = null;
            if (_selectedId == data['id']) {
              _selectedId = null;
              _selectedLabel = null;
            }
          });
          _scheduleSave();
          _refreshAdding();
        case 'cabinet_moved':
          // Keep the saved position in sync with drags in the 3D view.
          final i = _placedCabinets.indexWhere((c) => c['id'] == data['id']);
          if (i >= 0) {
            _remember();
            setState(() {
              _placedCabinets[i] = {
                ..._placedCabinets[i],
                'x_mm': data['x_mm'],
              };
              _activeVariantKey = null;
            });
            _scheduleSave();
            _refreshAdding();
          }
        case 'cabinet_selected':
          setState(() {
            _selectedId = data['id'] as String?;
            _selectedLabel = data['label'] as String?;
            _selectedMovable = data['movable'] as bool? ?? true;
          });
        case 'cabinet_opened':
          final id = data['id'];
          if (id is String) _openCard(id);
        case 'wall_opened':
          _openWall(
            opening: (data['opening'] as num?)?.toInt(),
            xMm: (data['x_mm'] as num?)?.toDouble(),
          );
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
      wallFinish: _wallFinish,
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
                'Each covers the cabinetry, cutouts and services. The '
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
                  // Like the rest of the screen: no prices until shown.
                  trailing: _priceVisible
                      ? Text(
                          formatMoney(item.price),
                          style: context.textTheme.labelLarge,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openAdding(item.type);
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

  /// The slower, better-lit version of the same two pictures. Null if it was
  /// cancelled or the view couldn't make it.
  Future<RenderResult?> _renderPictures(RenderRequest request) async {
    if (!_sceneLoaded || _rendering) return null;
    setState(() => _rendering = true);
    _renderProgress.value = 0;
    _lastRender = (engine: null, fellBack: false, stats: null);
    final images = await _pictureCall(
      'render',
      request.javaScript(skySamples: _renderSamples),
      request.timeout,
    );
    if (images.isEmpty) {
      // Gave up waiting: tell the page to stop too.
      unawaited(_scene.runJavaScript('cancelRender()'));
    }
    _renderProgress.value = null;
    if (mounted) setState(() => _rendering = false);
    if (images.isEmpty) return null;
    // The page says which engine it used; an older page says nothing, which
    // means the one asked for.
    final engine = _lastRender.engine ?? request.engine;
    final stats = _lastRender.stats;
    _rendered = (
      revision: _designRevision,
      images: images,
      engine: engine,
      stats: stats,
    );
    return RenderResult(images, engine,
        fellBack: _lastRender.fellBack, stats: stats);
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
    final alreadyRendered = _rendered != null && images != null
        ? _rendered!.engine
        : null;
    final alreadyStats = alreadyRendered == null ? null : _rendered!.stats;
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
        initialRender: alreadyRendered,
        initialStats: alreadyStats,
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
      askToKeepWallPhoto: _capture != null,
      onConfirm: _submitQuote,
    );
  }

  Future<void> _submitQuote({
    required String clientName,
    required String clientPhone,
    required String clientEmail,
    required double depositAmount,
    required String? signatureBase64,
    required bool keepWallPhoto,
  }) async {
    _clientName = clientName;
    if (_capture != null) _keepWallPhoto = keepWallPhoto;
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
    // The wall photo, with its corners, if the client agreed.
    final path = _wallPhotoPath;
    final wallPhoto = _capture != null && _keepWallPhoto && path != null
        ? await wallPhotoDataUrl(path)
        : null;
    final toSend = {
      ...record,
      if (pictures.isNotEmpty) 'design_images': pictures,
      if (wallPhoto != null) 'wall_photo': wallPhoto,
    }..remove('wall_photo_path');

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
      // Waiting to be sent: keep the pictures and the wall photo with it
      // when they fit. The photo's path stays too, in case they don't.
      final keepPictures =
          pictures.isNotEmpty && DesignPictures.fitsOffline(pictures);
      final keepPhoto = wallPhoto != null &&
          wallPhoto.length <= DesignPictures.maxBytesToKeepOffline;
      if (keepPictures || keepPhoto) {
        await OfflineStore.saveDraft({
          ...record,
          if (keepPictures) 'design_images': pictures,
          if (keepPhoto) 'wall_photo': wallPhoto,
        });
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
              // Pop back to home rather than go('/'): the home screen waits
              // on the routes it pushed and reloads when they close, so a
              // quote saved offline shows as "to send" instead of "All sent".
              final router = GoRouter.of(context);
              while (router.canPop()) {
                router.pop();
              }
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
            for (final line in summary.wallWorkLines)
              _SummaryTile(
                label: line.qty > 1
                    ? '${line.description} × ${line.qty}'
                    : line.description,
                value: formatMoney(line.total),
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
      child: _priceVisible
          ? LayoutBuilder(
              builder: (context, constraints) =>
                  _estimateWithPrice(summary, constraints.maxWidth),
            )
          : Row(
              children: [
                Expanded(
                  child: Row(
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
                const SizedBox(width: 4),
                _quoteButton(),
              ],
            ),
    );
  }

  Widget _quoteButton() => ElevatedButton.icon(
        onPressed: _sceneLoaded && !_rendering ? _openClosingModal : null,
        icon: const Icon(Icons.send_rounded, size: 16),
        label: const Text('Quote'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
        ),
      );

  /// The estimate bar with the price shown, [width] wide inside its padding:
  /// the total (a tap opens the details), Hide price and Quote in one row
  /// while the total fits on one line there. With large text on a phone it
  /// doesn't, and squeezed beside the buttons it wrapped a word or a few
  /// digits at a time, pushing the panel above it off the top of the screen.
  /// Then the same row wraps: the total across the bar, the buttons under it.
  Widget _estimateWithPrice(CPQSummary summary, double width) {
    final totalStyle =
        context.textTheme.titleLarge?.copyWith(color: context.colors.onSurface);
    final estimate = InkWell(
      onTap: _showBOQSheet,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: summary.totalPrice),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, val, _) =>
                Text(formatMoney(val), style: totalStyle),
          ),
          const SizedBox(height: 2),
          Text(
            summary.totalPrice > 0
                ? 'Estimate · ${cabinetCountLabel(_cabinetCount)} · Details'
                : 'Add cabinets to see an estimate',
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
    );
    final hide = IconButton(
      tooltip: 'Hide price',
      onPressed: () => setState(() => _priceVisible = false),
      icon: const Icon(
        Icons.visibility_off_outlined,
        color: AppTheme.textSecondary,
        size: 20,
      ),
    );

    // Hide price is 48 wide; Quote is its label plus a 16 icon, the gap
    // before the label (8 at most) and the theme's 20 a side.
    final quoteWidth =
        _oneLineWidth('Quote', context.textTheme.labelLarge) + 16 + 8 + 40;
    final besideButtons = width - 48 - 4 - quoteWidth;
    if (_oneLineWidth(formatMoney(summary.totalPrice), totalStyle) <=
        besideButtons) {
      return Row(
        children: [
          Expanded(child: estimate),
          hide,
          const SizedBox(width: 4),
          _quoteButton(),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        estimate,
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [hide, const SizedBox(width: 4), _quoteButton()],
        ),
      ],
    );
  }

  /// How wide [text] is on one line in [style], at the user's text size.
  double _oneLineWidth(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The panel over the estimate bar: the card being looked at, the Edit
  /// panel or the layouts bar. It scrolls when the space under the style
  /// pills can't hold it all (large text on a phone); a new one starts at
  /// its top.
  Widget _buildPanelSlot() {
    final Widget slot;
    if (_adding != null) {
      slot = _buildAddingCard(_adding!);
    } else if (_openId != null && _cabinet(_openId!) != null) {
      slot = _buildCabinetCard(_cabinet(_openId!)!);
    } else if (_wallOpen) {
      slot = _buildWallCard();
    } else if (_editing) {
      slot = _EditPanel(
        selectedLabel: _selectedLabel,
        selectedMovable: _selectedMovable,
        hasCabinets: _placedCabinets.isNotEmpty,
        onAdd: _openAdding,
        onSelectAdjacent: _selectAdjacent,
        onMove: _nudgeSelected,
        onRemoveSelected: _removeSelected,
        onOpenSelected: () {
          final id = _selectedId;
          if (id != null) _openCard(id);
        },
        onClearAll: _clearLayout,
        onAppliances: _showApplianceSheet,
        onBenchtop: _showBenchtopSheet,
        onWall: () => _openWall(),
        benchtopName: _benchtopMaterial == null
            ? null
            : _catalog.benchtopOptions[_benchtopMaterial]?.name,
        modules: _catalog.cabinetModules,
        kindOf: _catalog.kindOf,
        onDone: () => _setEditing(false),
      );
    } else {
      slot = _LayoutVariantBar(
        variants: _variants,
        activeKey: _activeVariantKey,
        onSelect: _selectVariant,
        onEdit: () => _setEditing(true),
        widthNote: _widthChecks[_activeVariantKey]?.message,
      );
    }
    return SingleChildScrollView(key: ValueKey(slot.runtimeType), child: slot);
  }

  @override
  Widget build(BuildContext context) {
    final summary = _cpqSummary;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_clientName.isEmpty ? '3D design' : _clientName),
        actions: [
          // Undo and redo for every change to the cabinets: a layout
          // switched, a cabinet added, moved, resized, swapped or removed.
          IconButton(
            tooltip: 'Undo',
            onPressed: _sceneLoaded && !_rendering && _undo.isNotEmpty
                ? () => _undoRedo(undo: true)
                : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: _sceneLoaded && !_rendering && _redo.isNotEmpty
                ? () => _undoRedo(undo: false)
                : null,
            icon: const Icon(Icons.redo_rounded),
          ),
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
        key: _viewKey,
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
          else
            // The style pills, the Kitchen / Room / House switch and, in the
            // space left under them, the panel. However tall the panel gets
            // (large text, a long card) it stays on screen and clear of the
            // controls above it: its upper part scrolls instead.
            Positioned(
              top: 12,
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Style ──────────────────────────────────────────────
                  // Only as wide as the pills, so the 3D view beside them
                  // stays draggable in the browser.
                  Align(
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

                  // ── Kitchen / Room / House (rooms read off a floor plan)
                  if (_floorPlan != null) ...[
                    const SizedBox(height: 6),
                    PointerShield(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'kitchen', label: Text('Kitchen')),
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
                  ],
                  const SizedBox(height: 8),

                  // ── Layouts / Edit panel + estimate ────────────────────
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: double.infinity,
                        // Only behind the panel, not the 3D view above it.
                        child: PointerShield(
                          child: Column(
                            key: _panelKey,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: _buildPanelSlot()),
                              const SizedBox(height: 8),
                              _buildEstimateBar(summary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

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

  /// Said when the chosen layout would change on a wall a little narrower
  /// or wider than the photo measured (width_check.dart).
  final String? widthNote;

  const _LayoutVariantBar({
    required this.variants,
    required this.activeKey,
    required this.onSelect,
    required this.onEdit,
    this.widthNote,
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
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Double-tap a cabinet or the wall to see it and change it.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
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
          if (widthNote case final note?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.straighten_rounded,
                        size: 18, color: AppTheme.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        note,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: AppTheme.danger),
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

/// Edit mode: add cabinets, remove the selected one, or clear everything.
class _EditPanel extends StatelessWidget {
  final String? selectedLabel;
  final bool selectedMovable;
  final bool hasCabinets;
  final void Function(String type) onAdd;
  final ValueChanged<int> onSelectAdjacent;
  final ValueChanged<int> onMove;
  final VoidCallback onRemoveSelected;

  /// Opens the selected cabinet's card (as a double tap on it does).
  final VoidCallback onOpenSelected;
  final VoidCallback onClearAll;
  final VoidCallback onAppliances;
  final VoidCallback onBenchtop;

  /// Opens the wall card (the way in without a double tap on the wall).
  final VoidCallback onWall;

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
    required this.onOpenSelected,
    required this.onClearAll,
    required this.onAppliances,
    required this.onBenchtop,
    required this.onWall,
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
              // Wraps at large text sizes rather than pushing Done off.
              Expanded(
                child: Text(
                  'Edit cabinets',
                  style: context.textTheme.labelLarge
                      ?.copyWith(color: context.colors.onSurface),
                ),
              ),
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
              (null, _) =>
                'Tap a cabinet to select it, or use Pick. Double-tap one to '
                    'see it and change it.',
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
                // The way into the card without a double tap.
                if (selected != null)
                  OutlinedButton.icon(
                    onPressed: onOpenSelected,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Change'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 44),
                    ),
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
              OutlinedButton.icon(
                onPressed: onWall,
                icon: const Icon(Icons.format_paint_outlined, size: 18),
                label: const Text('Wall'),
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
          // Wraps: a wall work line can be long.
          Expanded(
            child: Text(
              label,
              style: context.textTheme.labelSmall?.copyWith(
                  color: isBold
                      ? context.colors.onSurface
                      : context.colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
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

/// The cabinets at one moment, and the layout (A, B, C) they came from.
/// What undo and redo bring back: the cabinets and the layout they came
/// from, and the wall's openings and finish.
typedef _Cabinets = ({
  List<Map<String, dynamic>> cabinets,
  String? variant,
  List<Map<String, dynamic>> obstacles,
  Map<String, dynamic>? wallFinish,
});

/// A unit being added: the tray item it came from, the size chosen and the
/// free space it would go in (null: no room for it).
class _Adding {
  const _Adding({required this.type, required this.choice, required this.place});

  final String type;
  final CabinetChoice choice;
  final Placement? place;
}
