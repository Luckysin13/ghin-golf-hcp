
import 'package:flutter/material.dart';

import 'score_entry.dart';
import 'store.dart';

/// Score color picker: one row per bucket (eagle … triple), tap a row
/// to choose from preset swatches. Saved to the store, so the hole
/// strip and score entry all follow immediately.
Future<void> showScoreColorsDialog(BuildContext context, GolfStore store) {
  return showDialog(
    context: context,
    builder: (_) => ScoreColorsDialog(store: store),
  );
}

class ScoreColorsDialog extends StatefulWidget {
  final GolfStore store;
  const ScoreColorsDialog({super.key, required this.store});
  @override
  State<ScoreColorsDialog> createState() => _ScoreColorsDialogState();
}

class _ScoreColorsDialogState extends State<ScoreColorsDialog> {
  int? openDiff;
  static const _presets = [
    0xFF1B5E20,
    0xFF2E7D32,
    0xFF43A047,
    0xFF00897B,
    0xFF1565C0,
    0xFF607D8B,
    0xFF9E9E9E,
    0xFF212121,
    0xFFF9A825,
    0xFFEF6C00,
    0xFFE65100,
    0xFFD32F2F,
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Score colors'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (d, label) in scoreColorLabels)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(widget.store.scoreColorValue(d)),
                      ),
                    ),
                    title: Text(label),
                    trailing: Icon(
                      openDiff == d ? Icons.expand_less : Icons.expand_more,
                    ),
                    onTap: () =>
                        setState(() => openDiff = openDiff == d ? null : d),
                  ),
                  if (openDiff == d)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final p in _presets)
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => widget.store.setScoreColor(d, p),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(p),
                                  border: Border.all(
                                    color: widget.store.scoreColorValue(d) == p
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: widget.store.scoreColorValue(d) == p
                                    ? const Icon(
                                        Icons.check,
                                        size: 18,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => widget.store.resetScoreColors(),
          child: const Text('Reset defaults'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Small stepper button: themed outline circle, shared by score entry.
/// Pass [color] to tint the ring + icon (defaults to theme primary).
Widget outlineStep(
  BuildContext context,
  IconData icon,
  VoidCallback onTap, {
  Color? color,
}) {
  final scheme = Theme.of(context).colorScheme;
  final c = color ?? scheme.primary;
  return InkWell(
    borderRadius: BorderRadius.circular(22),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c, width: 1.5),
      ),
      child: Icon(icon, size: 16, color: c),
    ),
  );
}

// ---------------- POST ----------------

/// Black or white text for [background], whichever reads better.
Color readableOn(Color background) =>
    background.computeLuminance() > 0.179 ? Colors.black : Colors.white;

/// One quick-entry score button: a fixed-height oval pill with a centered
/// label. Custom-built instead of a ChoiceChip so all six pills render
/// identical geometry: same box, same 2px outline, same text position.
class ScorePill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const ScorePill({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 24,
      child: Material(
        shape: StadiumBorder(
          side: BorderSide(width: 2, color: color.withValues(alpha: 0.9)),
        ),
        color: selected ? color : color.withValues(alpha: 0.35),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? readableOn(color) : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Typed score entry for one hole, for scores past triple bogey.
class HoleScoreDialog extends StatefulWidget {
  final int holeNumber;
  final int par;
  final int currentScore;

  const HoleScoreDialog({
    super.key,
    required this.holeNumber,
    required this.par,
    required this.currentScore,
  });

  @override
  State<HoleScoreDialog> createState() => _HoleScoreDialogState();
}

class _HoleScoreDialogState extends State<HoleScoreDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.currentScore}',
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null || v < minHoleScore || v > maxHoleScore) {
      setState(
        () => _error = 'Enter a score from $minHoleScore to $maxHoleScore.',
      );
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Hole ${widget.holeNumber}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Par ${widget.par} — triple is ${widget.par + 3}.'),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Score', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
