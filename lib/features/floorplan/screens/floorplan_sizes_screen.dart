import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/platform/photo_image.dart';
import '../../../shared/theme.dart';
import '../kitchen_finder.dart';
import '../plan_analysis.dart';
import '../plan_geometry.dart';
import '../plan_sizes.dart';
import '../plan_text_reader.dart';

/// Plausible ranges, to catch a slip or metres typed without the "m".
const double kMinPlanWallMm = 500, kMaxPlanWallMm = 15000;
const double kMinCeilingMm = 1800, kMaxCeilingMm = 5000;

/// A whole-home plan smaller than this on its long side (a WhatsApp-
/// compressed image or a thumbnail) prints its sizes a few pixels tall: too
/// small to read. When no sizes are read off one, that's the likely reason.
const double kSmallPlanPx = 1000;

/// The shapes the layout generator fills. Names match the room payload's
/// `shape`, the same as the Room size screen.
enum PlanShape { singleWall, lShape }

enum _Field {
  main('Main wall', 'main wall'),
  ret('Return wall', 'return wall'),
  ceiling('Ceiling height', 'ceiling height');

  const _Field(this.label, this.inSentence);
  final String label;
  final String inSentence;
}

enum _Step { readingText, readingDrawing, done }

/// Sizes from a floor plan, filled in for the salesperson with plain rules
/// (no AI, nothing leaves the device):
///
/// - the text on the plan is read on the phone, and the kitchen's room size
///   is the one printed with its name ([findKitchen]);
/// - the drawing is read for its walls and rooms ([analysePlan]); with the
///   scale set by sizes printed for other rooms, a kitchen with no printed
///   size is measured from it.
///
/// The kitchen is outlined on the plan with its walls' sizes, **Turn**
/// picks which wall is the main one, and every field stays editable. With a
/// readable drawing, the plan goes to the 3D for its Room and House views.
class FloorplanSizesScreen extends StatefulWidget {
  const FloorplanSizesScreen({
    super.key,
    required this.imagePath,
    this.textReader = const DevicePlanTextReader(),
    this.analyser = const DevicePlanAnalyser(),
  });

  final String imagePath;
  final PlanTextReader textReader;
  final PlanAnalyser analyser;

  @override
  State<FloorplanSizesScreen> createState() => _FloorplanSizesScreenState();
}

class _FloorplanSizesScreenState extends State<FloorplanSizesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = {
    _Field.main: TextEditingController(),
    _Field.ret: TextEditingController(),
    _Field.ceiling: TextEditingController(text: '2700'),
  };
  final _focusNodes = {for (final f in _Field.values) f: FocusNode()};

  PlanShape _shape = PlanShape.singleWall;

  /// The field a size tapped on the plan goes into.
  _Field _target = _Field.main;

  _Step _step = _Step.readingText;
  PlanText _text = const PlanText();
  KitchenWalls? _walls;
  PlanAnalysis? _analysis;

  /// Which side of the kitchen's room is the main wall (0 top, 1 right,
  /// 2 bottom, 3 left); see [KitchenFrame].
  int _mainSide = 0;

  /// Whether the room size's first number runs across the plan (true) or
  /// down it, from the kitchen's shape in the drawing.
  bool _printedWidthAcross = true;

  /// What each filled-in field is based on, until the salesperson edits it.
  final _origin = <_Field, String>{};

  /// Fields the salesperson has typed in; reading the plan won't overwrite
  /// them.
  final _edited = <_Field>{};

  /// The size last tapped, outlined more strongly on the plan.
  PlanSize? _tapped;

  @override
  void initState() {
    super.initState();
    for (final entry in _focusNodes.entries) {
      entry.value.addListener(() {
        if (entry.value.hasFocus && _target != entry.key) {
          setState(() => _target = entry.key);
        }
      });
    }
    _readPlan();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _readPlan() async {
    PlanText text;
    try {
      text = await widget.textReader.read(widget.imagePath);
    } catch (_) {
      text = const PlanText();
    }
    if (!mounted) return;
    final walls = findKitchen(text);
    setState(() {
      _text = text;
      _walls = walls;
      _step = _Step.readingDrawing;
      _fill();
    });

    PlanAnalysis? analysis;
    try {
      analysis = await widget.analyser
          .analyse(widget.imagePath, text, walls?.kitchenLabel);
    } catch (_) {
      analysis = null;
    }
    if (!mounted) return;
    setState(() {
      _analysis = analysis;
      _step = _Step.done;
      _chooseMainSide();
      _fill();
    });
  }

  /// The kitchen's frame in the drawing, when it could be measured.
  KitchenFrame? get _frame {
    final g = _analysis?.geometry;
    final kitchen = g?.kitchen, scale = g?.mmPerPx;
    if (kitchen == null || scale == null) return null;
    return KitchenFrame(kitchen.rect, _mainSide, scale);
  }

  /// The printed room size, if the kitchen has one: (first, second).
  (PlanSize, PlanSize)? get _printed {
    final walls = _walls;
    if (walls == null || !walls.isLShape) return null;
    return (walls.mainWall.sizes.single, walls.returnWall!.sizes.single);
  }

  void _chooseMainSide() {
    final g = _analysis?.geometry;
    final kitchen = g?.kitchen?.rect, scale = g?.mmPerPx;
    if (kitchen == null || scale == null) return;
    if (_printed case (final first, _)?) {
      // Which way the room size's first number runs: the one that fits.
      _printedWidthAcross = (first.mm - kitchen.width * scale).abs() <=
          (first.mm - kitchen.height * scale).abs();
      _mainSide = _printedWidthAcross ? 0 : 3;
    } else {
      _mainSide = longestSide(kitchen);
    }
  }

  /// Fills the walls from what the plan says, leaving alone anything the
  /// salesperson has typed.
  void _fill() {
    final printed = _printed;
    final frame = _frame;
    final mainAcross = _mainSide.isEven;

    if (printed != null) {
      final (first, second) = printed;
      final firstIsMain = mainAcross == _printedWidthAcross;
      _shape = PlanShape.lShape;
      _setWall(_Field.main, firstIsMain ? first.text : second.text,
          'Printed on the plan · the kitchen\'s room size');
      _setWall(_Field.ret, firstIsMain ? second.text : first.text,
          'Printed on the plan · the kitchen\'s room size');
    } else if (frame != null) {
      String mm(double v) => '${(v / 10).round() * 10}';
      _shape = PlanShape.lShape;
      _setWall(_Field.main, mm(frame.mainMm),
          'Measured on the plan; check it on site');
      _setWall(_Field.ret, mm(frame.returnMm),
          'Measured on the plan; check it on site');
    }
  }

  void _setWall(_Field field, String text, String origin) {
    if (_edited.contains(field)) return;
    _setText(field, text);
    _origin[field] = origin;
  }

  /// The next side of the kitchen becomes the main wall.
  void _turn() => setState(() {
        _mainSide = (_mainSide + 1) % 4;
        _fill();
      });

  void _setText(_Field field, String text) {
    _controllers[field]!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _edit(_Field field) {
    _edited.add(field);
    _origin.remove(field);
  }

  /// Puts a printed size into the selected field, or adds it on when the
  /// field ends in "+".
  void _useSize(PlanSize size) {
    final field = _target;
    final current = _controllers[field]!.text.trimRight();
    final adding = current.endsWith('+');
    _setText(field, adding ? '$current ${size.text}' : size.text);

    setState(() {
      _edit(field);
      _tapped = size;
      // In an L the next size picked is usually the return wall.
      if (!adding &&
          field == _Field.main &&
          _shape == PlanShape.lShape &&
          _controllers[_Field.ret]!.text.trim().isEmpty) {
        _target = _Field.ret;
      }
    });
  }

  /// A wall split across two printed segments: "+" then tap the second one.
  void _startSum(_Field field) {
    final current = _controllers[field]!.text.trimRight();
    if (current.isNotEmpty && !current.endsWith('+')) {
      _setText(field, '$current + ');
    }
    setState(() {
      _edit(field);
      _target = field;
    });
  }

  String? _validate(String? value, _Field field, double min, double max) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter the ${field.inSentence}';
    final mm = parseLengthMm(text);
    if (mm == null) return 'Type a length like 3000, 3.0 m or 9\'8"';
    final range = '(${formatMm(min)} – ${formatMm(max)})';
    if (mm < min) {
      final asMetres = mm * 1000;
      if (!hasExplicitUnit(text) && asMetres >= min && asMetres <= max) {
        return 'That looks small for a ${field.inSentence}. '
            'For metres, type "$text m".';
      }
      return 'That looks small for a ${field.inSentence}. Is it in mm? $range';
    }
    if (mm > max) {
      return 'That looks big for a ${field.inSentence}. Is it in mm? $range';
    }
    return null;
  }

  void _viewIn3D() {
    if (!_formKey.currentState!.validate()) return;
    double mm(_Field f) =>
        parseLengthMm(_controllers[f]!.text)!.roundToDouble();
    final isL = _shape == PlanShape.lShape;
    final frame = _frame;
    final analysis = _analysis;

    final payload = {
      'wall': {
        'width_mm': mm(_Field.main),
        'height_mm': mm(_Field.ceiling),
        'depth_mm': 150.0,
        'shape': _shape.name,
        'return_mm': isL ? mm(_Field.ret) : 0,
      },
      // Doorways in the main wall, from the drawing: the layout keeps
      // cabinets out of them.
      'obstacles': frame == null
          ? <Map<String, dynamic>>[]
          : frame.mainWallDoors(analysis!.geometry.kitchen!),
      'salesperson_id': 'demo_agent_01',
      'created_via': 'floorplan_sizes',
      // The plan for the 3D's Room and House views.
      if (frame != null && analysis!.imageDataUrl.isNotEmpty)
        'floor_plan': frame.floorPlanJson(analysis.geometry,
            image: analysis.imageDataUrl),
    };
    context.push('/viewer', extra: jsonEncode(payload));
  }

  /// Which wall a size was picked for: "Main", "Return", or both when a
  /// room size gives both from one printed label.
  String? _pickedFor(PlanSize size) {
    final walls = _walls;
    if (walls == null) return null;
    final at = [
      for (final s in walls.pickedSizes)
        if (s.box == size.box) s,
    ];
    if (at.isEmpty) return null;
    final names = [
      if (at.any((s) => walls.mainWall.sizes.contains(s))) 'Main',
      if (_shape == PlanShape.lShape &&
          at.any((s) => walls.returnWall?.sizes.contains(s) ?? false))
        'Return',
    ];
    return names.isEmpty ? null : names.join(' + ');
  }

  // ── The plan ──────────────────────────────────────────────────────────

  Size? get _planSize => _text.planSize ?? _analysis?.originalSize;

  Widget _buildPlan(Size size) {
    final image = _planSize;
    Rect? shown;
    if (image != null && image.width > 0 && image.height > 0) {
      final fitted = applyBoxFit(BoxFit.contain, image, size);
      shown = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    }
    final g = _analysis?.geometry;
    final kitchenPx = g?.kitchen?.rect;
    final outlined = shown != null && g != null && kitchenPx != null;
    // One tag per place: the sizes of a room size share one. With the
    // kitchen outlined, its dimension lines already name the walls.
    final tagged = <Rect>{};

    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Positioned.fill(child: photoImage(widget.imagePath)),
          if (outlined)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _KitchenOutlinePainter(
                    kitchen: _onPlan(
                        Rect.fromLTRB(
                          kitchenPx.left / g.imageSize.width,
                          kitchenPx.top / g.imageSize.height,
                          kitchenPx.right / g.imageSize.width,
                          kitchenPx.bottom / g.imageSize.height,
                        ),
                        shown),
                    mainSide: _mainSide,
                    mainLabel: _wallLabel(_Field.main, 'Main'),
                    returnLabel: _shape == PlanShape.lShape
                        ? _wallLabel(_Field.ret, 'Side')
                        : null,
                  ),
                ),
              ),
            ),
          if (shown != null)
            for (final s in _text.sizes)
              _sizeOutline(s, shown, tag: !outlined && tagged.add(s.box)),
        ],
      ),
    );
  }

  String _wallLabel(_Field field, String name) {
    final mm = parseLengthMm(_controllers[field]!.text);
    return mm == null ? name : '$name ${formatMm(mm)}';
  }

  /// A printed size, outlined and tappable; the ones picked for a wall are
  /// marked with it. A pointer shortcut only: the same sizes are buttons in
  /// the panel below for screen-reader users.
  Widget _sizeOutline(PlanSize size, Rect shown, {required bool tag}) {
    final rect = _onPlan(size.box, shown).inflate(4);
    final wall = _pickedFor(size);
    final strong = wall != null || identical(size, _tapped);
    final color = strong ? AppTheme.success : AppTheme.accentTaupe;

    return Positioned.fromRect(
      rect: rect,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _useSize(size),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: strong ? 0.22 : 0.14),
                    border: Border.all(color: color, width: strong ? 2.5 : 1.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Under the size: above it is the room's name, and beside it
              // the next room's label can be.
              if (wall != null && tag)
                Positioned(
                  left: 0,
                  top: rect.height + 3,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      wall,
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── The panel ─────────────────────────────────────────────────────────

  Widget _status() {
    final image = _planSize;
    final g = _analysis?.geometry;
    final tooSmall = image != null &&
        image.longestSide > 0 &&
        image.longestSide < kSmallPlanPx;
    String text;
    var busy = false;
    switch (_step) {
      case _Step.readingText:
        text = 'Reading the plan…';
        busy = true;
      case _Step.readingDrawing:
        text = 'Reading the drawing…';
        busy = true;
      case _Step.done when _text.sizes.isEmpty && tooSmall:
        text = 'This plan is too small to read (${image.width.round()} px '
            'wide). Ask for the original (on WhatsApp: send it as a '
            'document), or type the sizes below.';
      case _Step.done when _text.isEmpty:
        text = "Couldn't read any text on this plan; it may be too small or "
            'blurry. Type the sizes below, or ask for the original (on '
            'WhatsApp: send it as a document).';
      case _Step.done when _walls == null:
        text = "Couldn't find the kitchen's name on this plan. Tap its sizes "
            'on the plan, or type them.';
      case _Step.done when _printed != null:
        text = "Filled in from the kitchen's room size. Check it and edit "
            "anything that's off.";
      case _Step.done when _frame != null:
        text = 'Measured from the drawing, using the sizes printed for other '
            'rooms as the scale. Check the walls on site.';
      case _Step.done when g?.kitchenIsOpenPlan ?? false:
        text = 'The kitchen is open to the next room, so its walls can\'t be '
            'measured from the drawing. Tap its sizes on the plan, or type '
            'them.';
      case _Step.done when g != null && g.hasWalls && g.mmPerPx == null:
        text = "The sizes printed on this plan don't match its drawing (it "
            "isn't to scale), so the walls can't be measured from it. Type "
            'them below.';
      case _Step.done:
        text = "No size is printed for the kitchen. Tap one on the plan, or "
            'type them below.';
    }

    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          if (busy) ...[
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colors.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(_Field field, {required double min, required double max}) {
    final controller = _controllers[field]!;
    final text = controller.text.trim();
    final mm = parseLengthMm(text);
    final selected = field == _target && _text.sizes.isNotEmpty;

    final lines = <String>[
      if (_origin[field] case final origin?) origin,
      if (mm != null && (hasExplicitUnit(text) || text.contains('+')))
        '= ${formatMm(mm)}'
      else if (selected && !_origin.containsKey(field))
        'Tap a size on the plan to fill this'
      else if (field == _Field.ceiling && !_origin.containsKey(field))
        'Plans rarely show it; 2,700 mm is typical',
    ];

    return TextFormField(
      controller: controller,
      focusNode: _focusNodes[field],
      // A number pad has no ' " + or m, which plan sizes need.
      keyboardType: TextInputType.text,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() => _edit(field)),
      onTap: () => setState(() => _target = field),
      decoration: InputDecoration(
        labelText: field.label,
        hintText: '3000, 3.0 m or 9\'8"',
        helperText: lines.isEmpty ? null : lines.join('\n'),
        helperMaxLines: 4,
        errorMaxLines: 3,
        fillColor: selected ? AppTheme.accentDim : null,
        suffixIcon: field == _Field.ceiling
            ? null
            : IconButton(
                tooltip: 'Add another size to the ${field.inSentence}',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _startSum(field),
              ),
      ),
      validator: (v) => _validate(v, field, min, max),
    );
  }

  /// The sizes printed on the plan, as buttons: the screen-reader and
  /// keyboard route to what the outlines on the plan do.
  Widget _foundSizes() {
    final unique = sizeChoices(_text, _walls);
    if (unique.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sizes on the plan',
            style: context.textTheme.labelMedium
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final size in unique)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(size.text),
                      tooltip:
                          'Use ${size.text} (${formatMm(size.mm)}) for the '
                          '${_target.inSentence}',
                      side: BorderSide(
                        color: identical(size, _tapped)
                            ? AppTheme.success
                            : AppTheme.border,
                        width: identical(size, _tapped) ? 2 : 1,
                      ),
                      onPressed: () => _useSize(size),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isL = _shape == PlanShape.lShape;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Sizes from the plan'),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              // ── The plan: pinch to zoom; the marks zoom with it ──────────
              Expanded(
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, box) => InteractiveViewer(
                      minScale: 1,
                      maxScale: 6,
                      child: _buildPlan(box.biggest),
                    ),
                  ),
                ),
              ),

              // ── Shape and sizes ──────────────────────────────────────────
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: constraints.maxHeight * 0.6),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _status(),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final (shape, label) in const [
                                (PlanShape.singleWall, 'Single wall'),
                                (PlanShape.lShape, 'L-shape'),
                              ])
                                ChoiceChip(
                                  label: Text(label),
                                  showCheckmark: false,
                                  selected: _shape == shape,
                                  onSelected: (_) => setState(() {
                                    _shape = shape;
                                    if (shape == PlanShape.singleWall &&
                                        _target == _Field.ret) {
                                      _target = _Field.main;
                                    }
                                  }),
                                ),
                              if (_frame != null)
                                TextButton.icon(
                                  onPressed: _turn,
                                  icon: const Icon(
                                      Icons.rotate_90_degrees_cw_rounded),
                                  label: const Text('Turn'),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _field(_Field.main,
                              min: kMinPlanWallMm, max: kMaxPlanWallMm),
                          if (isL) ...[
                            const SizedBox(height: 12),
                            _field(_Field.ret,
                                min: kMinPlanWallMm, max: kMaxPlanWallMm),
                          ],
                          const SizedBox(height: 12),
                          _field(_Field.ceiling,
                              min: kMinCeilingMm, max: kMaxCeilingMm),
                          const SizedBox(height: 12),
                          _foundSizes(),
                          Text(
                            'Plan sizes are a starting point. Confirm them on '
                            'site before ordering.',
                            style: context.textTheme.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _viewIn3D,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon:
                                const Icon(Icons.view_in_ar_rounded, size: 18),
                            label: const Text('View in 3D'),
                          ),
                        ],
                      ),
                    ),
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

/// A box given as fractions of the plan, where it's shown on screen.
Rect _onPlan(Rect fraction, Rect shown) => Rect.fromLTRB(
      shown.left + fraction.left * shown.width,
      shown.top + fraction.top * shown.height,
      shown.left + fraction.right * shown.width,
      shown.top + fraction.bottom * shown.height,
    );

/// The kitchen's room on the plan, with dimension lines like the Studio's
/// Plan view: the main wall's length beside it, the side wall's beside that.
class _KitchenOutlinePainter extends CustomPainter {
  _KitchenOutlinePainter({
    required this.kitchen,
    required this.mainSide,
    required this.mainLabel,
    required this.returnLabel,
  });

  final Rect kitchen;
  final int mainSide;
  final String mainLabel;
  final String? returnLabel;

  /// A side's two ends and the way out of the room from it.
  (Offset, Offset, Offset) _side(int side) {
    final k = kitchen;
    return switch (side % 4) {
      0 => (k.topLeft, k.topRight, const Offset(0, -1)),
      1 => (k.topRight, k.bottomRight, const Offset(1, 0)),
      2 => (k.bottomRight, k.bottomLeft, const Offset(0, 1)),
      _ => (k.bottomLeft, k.topLeft, const Offset(-1, 0)),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      kitchen,
      Paint()
        ..color = AppTheme.success.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      kitchen,
      Paint()
        ..color = AppTheme.success.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // The main wall, and the side wall at its left end (the side before it,
    // going round the room).
    _dimension(canvas, mainSide, mainLabel, strong: true);
    if (returnLabel case final label?) {
      _dimension(canvas, mainSide + 3, label, strong: false);
    }
  }

  void _dimension(Canvas canvas, int side, String label,
      {required bool strong}) {
    final (a, b, out) = _side(side);
    final paint = Paint()
      ..color = AppTheme.success
      ..strokeWidth = strong ? 3 : 1.5;
    // The wall itself, then the dimension line just outside it.
    canvas.drawLine(a, b, paint..strokeWidth = strong ? 4 : 2);
    final d = out * 10;
    final p = a + d, q = b + d;
    final thin = Paint()
      ..color = AppTheme.success
      ..strokeWidth = 1.2;
    canvas.drawLine(p, q, thin);
    final tick = Offset(out.dy, out.dx) * 4; // across the line
    for (final e in [p, q]) {
      canvas.drawLine(e - tick, e + tick, thin);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Written along the line, as drawings do: a wall running up and down
    // gets its label turned to read bottom to top, so it stays beside the
    // line instead of across the room.
    final upright = out.dx != 0;
    final mid = Offset.lerp(p, q, 0.5)! + out * (tp.height / 2 + 4);
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    if (upright) canvas.rotate(-math.pi / 2);
    final box = Rect.fromCenter(
        center: Offset.zero, width: tp.width + 12, height: tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)),
        Paint()..color = AppTheme.success);
    tp.paint(canvas, box.topLeft + const Offset(6, 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KitchenOutlinePainter old) =>
      old.kitchen != kitchen ||
      old.mainSide != mainSide ||
      old.mainLabel != mainLabel ||
      old.returnLabel != returnLabel;
}
