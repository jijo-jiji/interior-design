import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/widgets/nudge_buttons.dart';
import '../models/cabinet_choices.dart';

/// One thing the card offers the cabinet can become, and what that does to
/// the price (null while the price is hidden from the client, or unchanged).
class CardOption {
  const CardOption(this.choice, {this.priceChange});

  final CabinetChoice choice;
  final String? priceChange;
}

/// The card a double tap on a cabinet opens: what it is, and what it can
/// become without taking it out (another size, another unit in its place),
/// moving it and removing it. (Undo and redo are in the top bar.)
class CabinetCard extends StatelessWidget {
  const CabinetCard({
    super.key,
    required this.name,
    required this.description,
    required this.size,
    this.price,
    required this.sizes,
    required this.types,
    required this.movable,
    required this.onPick,
    required this.onMove,
    required this.onRemove,
    required this.onClose,
  });

  final String name;
  final String description;

  /// "600 × 850 × 600 mm".
  final String size;

  /// The cabinet's own price, when the price is shown; else null.
  final String? price;

  /// Other widths of the same unit; the current one is selected.
  final List<CardOption> sizes;

  /// Other units that go in its place; the current one is selected.
  final List<CardOption> types;

  /// Side-wall (L) units can't slide yet.
  final bool movable;
  final ValueChanged<CabinetChoice> onPick;

  /// -1 or +1: one step left or right.
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final muted = context.textTheme.bodySmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    // Why some choices are greyed out: the first reason is the one for all of
    // them (there is one free space around the cabinet).
    final reason = [...sizes, ...types]
        .map((o) => o.choice.problem)
        .whereType<String>()
        .firstOrNull;

    return Semantics(
      container: true,
      label: '$name, open',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
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
                      text: name,
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
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('$description · $size', style: muted),
            ),
            if (sizes.isNotEmpty)
              _Options(
                  title: 'Size', options: sizes, onPick: onPick, widths: true),
            if (types.length > 1)
              _Options(title: 'Change to', options: types, onPick: onPick),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                    'Greyed out: ${reason[0].toLowerCase()}${reason.substring(1)}.',
                    style: muted),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (movable)
                  NudgeButtons(
                    vertical: false,
                    onNudge: (dx, _) => onMove(dx),
                  ),
                OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    minimumSize: const Size(48, 44),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The card a unit from the tray (or the appliance list) opens before it is
/// added: what it is, its sizes, where it can go (the free spaces on these
/// walls), and Place. The 3D view shows it, see-through, where it would go.
class AddCabinetCard extends StatelessWidget {
  const AddCabinetCard({
    super.key,
    required this.name,
    required this.description,
    required this.size,
    this.priceChange,
    required this.sizes,
    required this.places,
    required this.place,
    required this.onSize,
    required this.onWhere,
    required this.onPlace,
    required this.onCancel,
  });

  final String name;
  final String description;
  final String size;

  /// What adding it does to the total ("+RM 340"), when the price is shown.
  final String? priceChange;

  /// Its sizes; the chosen one is selected. Empty if it comes in one size.
  final List<CardOption> sizes;

  /// The free spaces it fits in; [place] is the chosen one.
  final List<Placement> places;
  final Placement? place;
  final ValueChanged<CabinetChoice> onSize;
  final ValueChanged<Placement> onWhere;
  final VoidCallback onPlace;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final muted = context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Semantics(
      container: true,
      label: 'Add $name',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
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
                      text: 'Add $name',
                      style: context.textTheme.titleSmall?.copyWith(color: context.colors.onSurface),
                      children: [
                        if (priceChange != null)
                          TextSpan(
                            text: '  $priceChange',
                            style: context.textTheme.labelMedium?.copyWith(color: AppTheme.accent),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('$description · $size', style: muted),
            ),
            if (sizes.length > 1) _Options(title: 'Size', options: sizes, onPick: onSize, widths: true),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Where', style: context.textTheme.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
            ),
            const SizedBox(height: 4),
            if (places.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('No room for it on these walls. Remove a cabinet or make one narrower first.', style: muted),
              )
            else
              // Every free space in view at once (there are only a few).
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in places)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: p == place,
                      onSelected: (_) => onWhere(p),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: place == null ? null : onPlace,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Place it'),
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 44)),
                ),
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Options extends StatelessWidget {
  const _Options(
      {required this.title,
      required this.options,
      required this.onPick,
      this.widths = false});

  final String title;
  final List<CardOption> options;
  final ValueChanged<CabinetChoice> onPick;

  /// Labels as widths ("450") rather than names ("Drawers 600").
  final bool widths;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: context.textTheme.labelMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final o in options) ...[
                  _OptionChip(
                      option: o,
                      label: widths
                          ? '${o.choice.widthMm.round()}'
                          : o.choice.label,
                      onPick: onPick),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip(
      {required this.option, required this.label, required this.onPick});

  final CardOption option;
  final String label;
  final ValueChanged<CabinetChoice> onPick;

  @override
  Widget build(BuildContext context) {
    final c = option.choice;
    final change = option.priceChange;
    final chip = ChoiceChip(
      label: Text(change == null || c.current ? label : '$label  $change'),
      selected: c.current,
      // What doesn't fit can't be picked; the card says why underneath.
      onSelected: !c.fits
          ? null
          : (_) {
              if (!c.current) onPick(c);
            },
    );
    if (c.fits) return chip;
    return Tooltip(
      message: c.problem!,
      child: Semantics(
          label: '$label, ${c.problem}', excludeSemantics: true, child: chip),
    );
  }
}
