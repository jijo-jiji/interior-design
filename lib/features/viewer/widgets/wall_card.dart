import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/widgets/nudge_buttons.dart';

/// The two halves of the wall card.
enum WallTab { openings, finish }

/// One choice on the wall card: a finish, a colour, a width, a kind of
/// opening to make. [price] is what it costs or changes (null while the
/// price is hidden); [problem] why it can't be picked.
class WallOption<T> {
  const WallOption(this.value, this.label,
      {this.selected = false, this.price, this.problem, this.colour});

  final T value;
  final String label;
  final bool selected;
  final String? price;
  final String? problem;

  /// A swatch, for a colour.
  final Color? colour;
}

/// A door or window on the wall, as the card lists it.
class WallOpeningItem {
  const WallOpeningItem(
      {required this.name,
      required this.label,
      required this.detail,
      required this.isNew});

  /// "Hidden door".
  final String name;

  /// "Hidden door 800".
  final String label;

  /// "800 × 2100 mm · to be made" / "· already there".
  final String detail;
  final bool isNew;
}

/// The card a double tap on the wall opens: its finish (paint, tiles,
/// panels, with a colour) and its doors and windows, with a hidden door, a
/// door or a window to be made in it: added, moved, resized, taken out.
class WallCard extends StatelessWidget {
  const WallCard({
    super.key,
    required this.title,
    required this.size,
    required this.tab,
    required this.onTab,
    this.price,
    this.samplePrices = false,
    required this.finishes,
    required this.colours,
    required this.openings,
    required this.selected,
    required this.widths,
    required this.adds,
    required this.onFinish,
    required this.onColour,
    required this.onSelect,
    required this.onWidth,
    required this.onMove,
    required this.onRemove,
    required this.onAdd,
    required this.onClose,
  });

  /// "Main wall".
  final String title;

  /// "3600 × 2700 mm · 8.40 m² to finish".
  final String size;

  /// What the card shows: the doors and windows ([WallTab.openings]) or the
  /// finish; one at a time keeps it short enough to leave the wall in view.
  final WallTab tab;
  final ValueChanged<WallTab> onTab;

  /// What the wall's work adds to the quote, when the price is shown.
  final String? price;

  /// The wall work prices are still samples (said only with the price shown).
  final bool samplePrices;

  /// As it is, paint, tiles, panels (value null: as it is).
  final List<WallOption<String?>> finishes;

  /// The colours of the chosen finish; empty for none.
  final List<WallOption<String>> colours;
  final List<WallOpeningItem> openings;

  /// The index of the opening being changed, if any.
  final int? selected;

  /// Its widths (for one to be made).
  final List<WallOption<double>> widths;

  /// Hidden door, door, window: what can be made.
  final List<WallOption<String>> adds;
  final ValueChanged<String?> onFinish;
  final ValueChanged<String> onColour;
  final ValueChanged<int?> onSelect;
  final ValueChanged<double> onWidth;

  /// -1 or +1: one step left or right.
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;
  final ValueChanged<String> onAdd;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final muted = context.textTheme.bodySmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    final label = context.textTheme.labelMedium
        ?.copyWith(color: context.colors.onSurfaceVariant);
    final open = selected == null || selected! >= openings.length
        ? null
        : openings[selected!];
    final refused = adds.map((a) => a.problem).whereType<String>().firstOrNull;

    return Semantics(
      container: true,
      label: '$title, open',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
        // At most about half the screen, so the wall stays in view; the rest
        // scrolls under the title and Close.
        // With large text the estimate bar under the card grows too, so the
        // card gets less.
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height *
                (MediaQuery.textScalerOf(context).scale(10) >= 15
                    ? 0.3
                    : 0.55)),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: title,
                      style: context.textTheme.titleSmall
                          ?.copyWith(color: context.colors.onSurface),
                      children: [
                        if (price != null)
                          TextSpan(
                            text: '  $price',
                            style: context.textTheme.labelMedium
                                ?.copyWith(color: AppTheme.accent),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                          samplePrices && price != null
                              ? '$size · sample prices'
                              : size,
                          style: muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (t, name) in [
                          (WallTab.openings, 'Doors and windows'),
                          (WallTab.finish, 'Finish'),
                        ])
                          ChoiceChip(
                            label: Text(name),
                            selected: tab == t,
                            onSelected: (_) => onTab(t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (tab == WallTab.finish) ...[
                      _Chips<String?>(options: finishes, onPick: onFinish),
                      if (colours.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Colour', style: label),
                        const SizedBox(height: 4),
                        _Chips<String>(options: colours, onPick: onColour),
                      ],
                    ] else ...[
                      if (openings.isEmpty)
                        Text('None yet. A solid wall.', style: muted)
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < openings.length; i++)
                              ChoiceChip(
                                label: Text(openings[i].isNew
                                    ? '${openings[i].label} · new'
                                    : openings[i].label),
                                selected: i == selected,
                                onSelected: (on) => onSelect(on ? i : null),
                              ),
                          ],
                        ),
                      if (open != null) ...[
                        const SizedBox(height: 6),
                        Text(open.detail, style: muted),
                        if (open.isNew) ...[
                          if (widths.length > 1) ...[
                            const SizedBox(height: 6),
                            Text('Width', style: label),
                            const SizedBox(height: 4),
                            _Chips<double>(options: widths, onPick: onWidth),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              NudgeButtons(
                                  vertical: false,
                                  onNudge: (dx, _) => onMove(dx)),
                              OutlinedButton.icon(
                                onPressed: onRemove,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label:
                                    Text('Remove ${open.name.toLowerCase()}'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.danger,
                                  side:
                                      const BorderSide(color: AppTheme.danger),
                                  minimumSize: const Size(48, 44),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: 10),
                      Text('Make an opening in the wall', style: label),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in adds)
                            Tooltip(
                              message: a.problem ?? '',
                              child: OutlinedButton.icon(
                                onPressed: a.problem == null
                                    ? () => onAdd(a.value)
                                    : null,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text(a.price == null
                                    ? a.label
                                    : '${a.label}  ${a.price}'),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(48, 44)),
                              ),
                            ),
                        ],
                      ),
                      if (refused != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 8),
                          child: Text(
                              'Greyed out: ${refused[0].toLowerCase()}'
                              '${refused.substring(1)}.',
                              style: muted),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of choice chips that wraps; one that can't be picked is greyed out
/// and says why (tooltip and screen reader).
class _Chips<T> extends StatelessWidget {
  const _Chips({required this.options, required this.onPick});

  final List<WallOption<T>> options;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in options)
          Builder(builder: (context) {
            final text = o.price == null || o.selected
                ? o.label
                : '${o.label}  ${o.price}';
            final chip = ChoiceChip(
              avatar: o.colour == null
                  ? null
                  : Container(
                      decoration: BoxDecoration(
                        color: o.colour,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.border),
                      ),
                    ),
              label: Text(text),
              selected: o.selected,
              onSelected: o.problem != null
                  ? null
                  : (_) {
                      if (!o.selected) onPick(o.value);
                    },
            );
            if (o.problem == null) return chip;
            return Tooltip(
              message: o.problem!,
              child: Semantics(
                  label: '$text, ${o.problem}',
                  excludeSemantics: true,
                  child: chip),
            );
          }),
      ],
    );
  }
}
