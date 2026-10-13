
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'course_catalog.dart';
import 'design_tokens.dart';
import 'models.dart';
import 'scan_service.dart';
import 'scorecard_scan.dart';
import 'opengolf.dart';
import 'table_geometry.dart';
import 'scorecard_widgets.dart';

// ---------------- ADD COURSE ----------------
class AddCourseScreen extends StatefulWidget {
  /// When set, the form edits this saved custom course instead of adding.
  final Course? existing;
  final CourseCatalogCourse? catalogCourse;
  final CourseCatalogTee? catalogTee;
  final List<Tee> importedCatalogTees;
  final Map<String, int> catalogParTotals;
  final Map<String, List<int>> missingParHolesByTee;
  final String? catalogOnlineStatus;
  final bool onlineAttribution;
  const AddCourseScreen({
    super.key,
    this.existing,
    this.catalogCourse,
    this.catalogTee,
    this.importedCatalogTees = const [],
    this.catalogParTotals = const {},
    this.missingParHolesByTee = const {},
    this.catalogOnlineStatus,
    this.onlineAttribution = false,
  }) : assert(catalogCourse != null || catalogTee == null || existing != null);
  @override
  State<AddCourseScreen> createState() => _AddCourseScreenState();
}

/// One tee box being drafted. Pars, yardages and hole indexes belong to each tee.
class _TeeDraft {
  final TextEditingController nameCtrl;
  final TextEditingController ratingCtrl = TextEditingController();
  final TextEditingController slopeCtrl = TextEditingController();
  final TextEditingController frontNineRatingCtrl = TextEditingController();
  final TextEditingController frontNineSlopeCtrl = TextEditingController();
  final TextEditingController backNineRatingCtrl = TextEditingController();
  final TextEditingController backNineSlopeCtrl = TextEditingController();
  List<int> pars;
  Set<int> parNeedsReview = {};
  int? catalogPar;
  List<int> yards;
  List<int?> strokeIndexes;
  _TeeDraft(String name, int holes)
    : nameCtrl = TextEditingController(text: name),
      pars = List.filled(holes, 4),
      yards = List.filled(holes, 0),
      strokeIndexes = List<int?>.filled(holes, null);

  /// A tee the database already knows: rating, slope and yardage come across
  /// filled in, so nothing has to be retyped and nothing is guessed.
  factory _TeeDraft.fromTee(Tee t) {
    final d = _TeeDraft(t.name, t.holes.length)
      ..ratingCtrl.text = t.rating.toStringAsFixed(1)
      ..slopeCtrl.text = '${t.slope}'
      ..frontNineRatingCtrl.text = t.frontNineRating?.toStringAsFixed(1) ?? ''
      ..frontNineSlopeCtrl.text = t.frontNineSlope?.toString() ?? ''
      ..backNineRatingCtrl.text = t.backNineRating?.toStringAsFixed(1) ?? ''
      ..backNineSlopeCtrl.text = t.backNineSlope?.toString() ?? ''
      ..pars = [for (final h in t.holes) h.par]
      ..yards = [for (final h in t.holes) h.yardage]
      ..strokeIndexes = [for (final h in t.holes) h.strokeIndex];
    return d;
  }

  void resize(int holes) {
    if (yards.length == holes) return;
    yards = List.generate(holes, (i) => i < yards.length ? yards[i] : 0);
    pars = List.generate(holes, (i) => i < pars.length ? pars[i] : 4);
    strokeIndexes = List.generate(
      holes,
      (i) => i < strokeIndexes.length ? strokeIndexes[i] : null,
    );
  }

  void dispose() {
    nameCtrl.dispose();
    ratingCtrl.dispose();
    slopeCtrl.dispose();
    frontNineRatingCtrl.dispose();
    frontNineSlopeCtrl.dispose();
    backNineRatingCtrl.dispose();
    backNineSlopeCtrl.dispose();
  }
}

class _AddCourseScreenState extends State<AddCourseScreen> {
  final nameCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final stateCtrl = TextEditingController();
  final _photoZoom = ScorecardZoom();
  int holesCount = 18;
  final List<_TeeDraft> tees = [];
  List<int> get pars => tees[editYardsTee.clamp(0, tees.length - 1)].pars;
  int editYardsTee = 0;
  bool scanning = false;
  String scanStatus = 'Reading scorecard…';
  XFile? scanPhoto;
  String keptPhoto = '';
  // Raw OCR text from the last scan, viewable via the inspector (Phase 0
  // of the OCR plan): shows what Tesseract actually read, so a miss can
  // be blamed on the input/engine instead of the parser.
  String lastOcrText = '';
  // Every attempt's raw text, not just the best one. A card that reads badly
  // is usually readable in one pass and garbled in another, so keeping the
  // failures is what makes a parser fix testable against a real photo later
  // instead of a guess.
  List<String> lastOcrAttempts = const [];
  // Text from the digits-only pass, kept for the raw-text inspector.
  String lastOcrDigitsText = '';
  // The hOCR from the column-geometry pass, same reason.
  String lastOcrHocrText = '';
  // Holes whose par was guessed from yardage lengths rather than read, and
  // whether the guess came from the yardages at all. The user is asked about
  // these instead of being shown a form that silently filled itself in.
  Set<int> parUncertain = const {};
  bool parFromYardages = false;
  static const _suggestNames = [
    'White',
    'Blue',
    'Red',
    'Black',
    'Gold',
    'Green',
  ];

  @override
  void initState() {
    super.initState();
    final edit = widget.existing;
    if (edit != null) {
      nameCtrl.text = edit.name;
      cityCtrl.text = edit.city;
      stateCtrl.text = edit.state;
      holesCount = edit.tees.first.holes.length;
      for (final t in edit.tees) {
        final d = _TeeDraft.fromTee(t);
        final importedCourseTee = widget.importedCatalogTees
            .where((tee) => tee.name.toLowerCase() == t.name.toLowerCase())
            .firstOrNull;
        final importedTee =
            widget.catalogTee != null &&
                t.name.toLowerCase() ==
                    widget.catalogTee!.displayName.toLowerCase()
            ? widget.catalogTee
            : null;
        if (importedTee != null) {
          if (importedTee.frontNineRating != null &&
              d.frontNineRatingCtrl.text.trim().isEmpty) {
            d.frontNineRatingCtrl.text = importedTee.frontNineRating!
                .toStringAsFixed(1);
          }
          if (importedTee.frontNineSlope != null &&
              d.frontNineSlopeCtrl.text.trim().isEmpty) {
            d.frontNineSlopeCtrl.text = '${importedTee.frontNineSlope}';
          }
          if (importedTee.backNineRating != null &&
              d.backNineRatingCtrl.text.trim().isEmpty) {
            d.backNineRatingCtrl.text = importedTee.backNineRating!
                .toStringAsFixed(1);
          }
          if (importedTee.backNineSlope != null &&
              d.backNineSlopeCtrl.text.trim().isEmpty) {
            d.backNineSlopeCtrl.text = '${importedTee.backNineSlope}';
          }
        }
        for (var i = 0; i < d.yards.length && i < t.holes.length; i++) {
          if (d.yards[i] == 0) {
            d.yards[i] = t.holes[i].yardage;
          }
          if (importedCourseTee != null &&
              d.yards[i] == 0 &&
              i < importedCourseTee.holes.length) {
            d.yards[i] = importedCourseTee.holes[i].yardage;
          }
        }
        tees.add(d);
      }
      for (final importedTee in widget.importedCatalogTees) {
        if (edit.tees.any(
          (t) => t.name.toLowerCase() == importedTee.name.toLowerCase(),
        )) {
          continue;
        }
        final draft = _TeeDraft.fromTee(importedTee)
          ..catalogPar = widget.catalogParTotals[importedTee.name]
          ..parNeedsReview = {
            ...?widget.missingParHolesByTee[importedTee.name],
          };
        tees.add(draft);
      }
      final catalogTee = widget.catalogTee;
      if (catalogTee != null &&
          !edit.tees.any(
            (t) => t.name.toLowerCase() == catalogTee.displayName.toLowerCase(),
          )) {
        final d = _TeeDraft(catalogTee.displayName, holesCount)
          ..ratingCtrl.text = catalogTee.rating.toStringAsFixed(1)
          ..slopeCtrl.text = '${catalogTee.slope}'
          ..frontNineRatingCtrl.text =
              catalogTee.frontNineRating?.toStringAsFixed(1) ?? ''
          ..frontNineSlopeCtrl.text =
              catalogTee.frontNineSlope?.toString() ?? ''
          ..backNineRatingCtrl.text =
              catalogTee.backNineRating?.toStringAsFixed(1) ?? ''
          ..backNineSlopeCtrl.text = catalogTee.backNineSlope?.toString() ?? '';
        tees.add(d);
      }
      keptPhoto = edit.imagePath;
      return;
    }
    final catalogCourse = widget.catalogCourse;
    final catalogTee = widget.catalogTee;
    if (catalogCourse != null && widget.importedCatalogTees.isNotEmpty) {
      nameCtrl.text = catalogCourse.name;
      cityCtrl.text = catalogCourse.city;
      stateCtrl.text = catalogCourse.state;
      holesCount = widget.importedCatalogTees.first.holes.length;
      for (final tee in widget.importedCatalogTees) {
        final draft = _TeeDraft.fromTee(tee)
          ..catalogPar = widget.catalogParTotals[tee.name]
          ..parNeedsReview = {...?widget.missingParHolesByTee[tee.name]};
        tees.add(draft);
      }
      return;
    }
    if (catalogCourse != null && catalogTee != null) {
      nameCtrl.text = catalogCourse.name;
      cityCtrl.text = catalogCourse.city;
      stateCtrl.text = catalogCourse.state;
      holesCount = catalogTee.holes;
      final draft = _TeeDraft(catalogTee.displayName, holesCount)
        ..ratingCtrl.text = catalogTee.rating.toStringAsFixed(1)
        ..slopeCtrl.text = '${catalogTee.slope}'
        ..frontNineRatingCtrl.text =
            catalogTee.frontNineRating?.toStringAsFixed(1) ?? ''
        ..frontNineSlopeCtrl.text = catalogTee.frontNineSlope?.toString() ?? ''
        ..backNineRatingCtrl.text =
            catalogTee.backNineRating?.toStringAsFixed(1) ?? ''
        ..backNineSlopeCtrl.text = catalogTee.backNineSlope?.toString() ?? '';
      tees.add(draft);
      return;
    }
    tees.add(_TeeDraft('White', holesCount));
  }

  void _setHoles(int n) {
    setState(() {
      holesCount = n;
      for (final t in tees) {
        t.resize(n);
      }
      editYardsTee = 0;
    });
  }

  void _addTee() {
    setState(() {
      final used = tees
          .map((t) => t.nameCtrl.text.trim().toLowerCase())
          .toSet();
      final next = _suggestNames.firstWhere(
        (s) => !used.contains(s.toLowerCase()),
        orElse: () => 'Tee ${tees.length + 1}',
      );
      tees.add(_TeeDraft(next, holesCount));
      editYardsTee = tees.length - 1;
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    cityCtrl.dispose();
    stateCtrl.dispose();
    _photoZoom.dispose();
    for (final t in tees) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yardsTee = tees[editYardsTee.clamp(0, tees.length - 1)];
    final photoPath = scanPhoto?.path ?? keptPhoto;
    final showPhoto = photoPath.isNotEmpty && photoUsable(photoPath);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Add local course' : 'Edit course',
        ),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
            isDense: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.lg,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final photoPanelHeight = (constraints.maxHeight * 0.44)
                .clamp(0.0, 300.0)
                .toDouble();
            return Column(
              children: [
                if (showPhoto)
                  SizedBox(
                    key: const ValueKey('pinned-scorecard-photo'),
                    width: double.infinity,
                    height: photoPanelHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _photoPreview(photoPath, isNew: scanPhoto != null),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        widget.catalogTee != null
                            ? 'Published tee ratings and total par are prefilled from the local catalog. Review or edit pars and yardages when you have the scorecard; you can save now and edit later.'
                            : widget.importedCatalogTees.isNotEmpty
                            ? 'All tee ratings from the local catalog are prefilled. Online pars and available yardages are included; unknown pars default to 4 and missing yardages stay blank. You can save now and edit later.'
                            : 'Copy par, rating and slope from the scorecard. Saved on-device, works offline.',
                      ),
                      if (widget.catalogOnlineStatus != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${widget.catalogOnlineStatus}${widget.onlineAttribution ? '\n$openGolfAttribution' : ''}',
                          style: AppType.meta.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (scanning) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 4),
                        Text(
                          scanStatus,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        'Photo tips: lay the card flat, fill the frame, shoot straight-on in good light with no glare.',
                        style: AppType.meta.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const SizedBox(height: Insets.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: scanning ? null : _chooseScanSource,
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: const Text('Scan scorecard photo'),
                            ),
                            if (lastOcrText.isNotEmpty)
                              TextButton.icon(
                                onPressed: () =>
                                    showOcrTextDialog(context, lastOcrText),
                                icon: const Icon(
                                  Icons.text_snippet_outlined,
                                  size: 18,
                                ),
                                label: const Text('View read text'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Course name *',
                        ),
                      ),
                      const SizedBox(height: Insets.sm),
                      TextField(
                        controller: cityCtrl,
                        decoration: const InputDecoration(labelText: 'City'),
                      ),
                      const SizedBox(height: Insets.sm),
                      TextField(
                        controller: stateCtrl,
                        decoration: const InputDecoration(labelText: 'State'),
                      ),
                      const SizedBox(height: Insets.md),
                      Row(
                        children: [
                          const Text('Holes: '),
                          for (final n in [9, 18])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: ChoiceChip(
                                label: Text('$n'),
                                selected: holesCount == n,
                                showCheckmark: false,
                                onSelected:
                                    widget.catalogTee == null &&
                                        widget.importedCatalogTees.isEmpty
                                    ? (_) => _setHoles(n)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tee boxes:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        holesCount == 9
                            ? 'For a 9-hole course, enter its published 9-hole rating and slope. For an 18-hole course, enter its overall rating and slope.'
                            : 'Add one per color you play. Enter the published rating and slope for each tee.',
                        style: AppType.meta.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (var ti = 0; ti < tees.length; ti++)
                        Card(
                          margin: const EdgeInsets.only(bottom: Insets.md),
                          child: Padding(
                            padding: const EdgeInsets.all(Insets.md),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: tees[ti].nameCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Teebox ${ti + 1}',
                                        ),
                                      ),
                                    ),
                                    if (tees.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => setState(() {
                                          tees[ti].dispose();
                                          tees.removeAt(ti);
                                          editYardsTee = 0;
                                          holesCount = tees.first.pars.length;
                                        }),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: Insets.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: tees[ti].ratingCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Rating *',
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: tees[ti].slopeCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Slope *',
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ],
                                ),
                                if (holesCount == 18) ...[
                                  const SizedBox(height: 8),
                                  const SizedBox(height: Insets.sm),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller:
                                              tees[ti].frontNineRatingCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Front 9 rating',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller:
                                              tees[ti].frontNineSlopeCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Front 9 slope',
                                          ),
                                          keyboardType: TextInputType.number,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: Insets.sm),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller:
                                              tees[ti].backNineRatingCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Back 9 rating',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller:
                                              tees[ti].backNineSlopeCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Back 9 slope',
                                          ),
                                          keyboardType: TextInputType.number,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: Insets.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addTee,
                          icon: const Icon(Icons.add),
                          label: const Text('Add another tee box'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Holes (pars and yardages for the selected tee):',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Tap a par to cycle 3 → 4 → 5. Tap a yardage to type it (— = unknown).',
                        style: AppType.meta.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (parFromYardages) ...[
                        Card(
                          color: Theme.of(
                            context,
                          ).colorScheme.tertiaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.help_outline,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    parUncertain.isEmpty
                                        ? 'The par row was too small to read, so par was worked out from the yardages. All 18 holes look settled — give it a glance.'
                                        : 'The par row was too small to read, so par was worked out from the yardages. A par 4 and a par 5 are the same length on some holes, so check the highlighted ones (${parUncertain.join(', ')}).',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Yardages for: '),
                          for (var ti = 0; ti < tees.length; ti++)
                            ChoiceChip(
                              label: Text(
                                tees[ti].nameCtrl.text.trim().isEmpty
                                    ? 'Tee ${ti + 1}'
                                    : tees[ti].nameCtrl.text.trim(),
                              ),
                              selected: editYardsTee == ti,
                              showCheckmark: false,
                              onSelected: (_) => setState(() {
                                editYardsTee = ti;
                                holesCount = tees[ti].pars.length;
                              }),
                            ),
                        ],
                      ),
                      for (var i = 0; i < yardsTee.pars.length; i++)
                        _holeRow(i, yardsTee),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _save(),
                        icon: const Icon(Icons.check),
                        label: Text(
                          widget.existing == null
                              ? 'Save course'
                              : 'Save changes',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Type an exact yardage instead of stepping.
  Future<void> _typeYards(int i, _TeeDraft t) async {
    final ctrl = TextEditingController(
      text: t.yards[i] == 0 ? '' : '${t.yards[i]}',
    );
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hole ${i + 1} yardage'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 385',
            suffixText: 'yd',
          ),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(int.tryParse(ctrl.text.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(ctrl.text.trim())),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (v != null) setState(() => t.yards[i] = v.clamp(0, 650));
  }

  /// One hole card, one uniform row: HOLE n, tap Par to cycle 3-4-5,
  /// tap the yardage to type it. Fixed height so every row is equal.
  Widget _holeRow(int i, _TeeDraft yardsTee) {
    final scheme = Theme.of(context).colorScheme;
    final yds = yardsTee.yards[i];
    final parNeedsReview =
        yardsTee.parNeedsReview.contains(i + 1) || parUncertain.contains(i + 1);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  'HOLE ${i + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    yardsTee.pars[i] = yardsTee.pars[i] >= 5
                        ? 3
                        : yardsTee.pars[i] + 1;
                    yardsTee.parNeedsReview.remove(i + 1);
                    // Confirming the value is the answer: stop flagging it.
                    parUncertain = {...parUncertain}..remove(i + 1);
                  }),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: parNeedsReview
                          ? BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: scheme.tertiary),
                            )
                          : null,
                      child: Text(
                        '${parNeedsReview ? '? ' : ''}Par: ${yardsTee.pars[i]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: parNeedsReview
                              ? scheme.onTertiaryContainer
                              : scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _typeYards(i, yardsTee),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        yds == 0 ? '— yd' : '$yds yd',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 62,
                child: TextFormField(
                  key: ValueKey(
                    'hcp-${identityHashCode(yardsTee)}-${yardsTee.strokeIndexes.length}-$i',
                  ),
                  initialValue: yardsTee.strokeIndexes[i]?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'HCP',
                    hintText: '-',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) {
                    final text = value.trim();
                    yardsTee.strokeIndexes[i] = text.isEmpty
                        ? null
                        : int.tryParse(text) ?? -1;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPreview(String path, {required bool isNew}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isNew
                        ? 'Scanned photo (saves with course)'
                        : 'Saved scorecard photo',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _removePhoto,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          InkWell(
                            onTap: () => showCoursePhoto(
                              context,
                              nameCtrl.text.trim().isEmpty
                                  ? 'Scorecard'
                                  : nameCtrl.text.trim(),
                              path,
                            ),
                            child: scorecardImageView(
                              path,
                              _photoZoom,
                              key: const ValueKey(
                                'course-scorecard-interactive-viewer',
                              ),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(Radii.pill),
                              elevation: 2,
                              child: ScorecardZoomControls(
                                zoom: _photoZoom,
                                compact: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Pinch to zoom · drag to pan · tap photo for full screen',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removePhoto() async {
    final old = scanPhoto?.path ?? keptPhoto;
    _photoZoom.reset();
    setState(() {
      scanPhoto = null;
      keptPhoto = '';
    });
    await deleteScanPhoto(old);
  }

  Future<void> _chooseScanSource() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src != null) await _scanImage(src);
  }

  Future<void> _scanImage(ImageSource src) async {
    // Full resolution: downscaling destroys the small digits Tesseract
    // needs for yardages (Phase 1 of the OCR plan).
    final file = await ImagePicker().pickImage(source: src, imageQuality: 100);
    if (file == null) return;
    setState(() {
      scanning = true;
      scanStatus = 'Reading scorecard…';
    });
    try {
      // Retry ensemble: when the first read is thin, re-run OCR and merge
      // the results. Each attempt varies *preprocessing* as well as page
      // segmentation — a photo that reads badly under one preparation
      // usually reads badly under every segmentation of that same
      // preparation. Attempts are merged per field rather than ranked
      // whole, because a pass that reads every tee box but loses the small
      // print would otherwise beat the pass that got the par.
      final attempts = <ScorecardScan>[];
      final texts = <String>[];
      var bestText = '';
      ScorecardScan? bestScan;
      var attempt = 0;
      for (final variant in scanVariants) {
        if (!mounted) return;
        attempt++;
        if (attempt > 1) {
          setState(
            () => scanStatus =
                'Trying another read (${variant.label}, $attempt of ${scanVariants.length})…',
          );
        }
        final ocrPath = await preprocessScorecard(
          file.path,
          prep: variant.prep,
        );
        final attemptText = await extractScorecardText(
          ocrPath,
          args: variant.psm == null
              ? const <String, String>{}
              : <String, String>{'psm': variant.psm!},
        );
        if (attemptText.isEmpty) continue;
        final attemptScan = parseScorecardText(attemptText);
        attempts.add(attemptScan);
        texts.add(attemptText);
        // Track the best attempt by its own scan quality, so the
        // best raw text and the best scan stay consistent instead of
        // reparsing the best text on every round.
        if (bestScan == null ||
            scanQuality(attemptScan) > scanQuality(bestScan)) {
          bestScan = attemptScan;
          bestText = attemptText;
        }
        if (_scanComplete(mergeScans(attempts))) break;
      }

      if (!mounted) return;
      var scan = mergeScans(attempts);

      // Column geometry pass. The text read gives numbers in reading order,
      // so a lost digit renames every hole after it; asking for the same OCR
      // as hOCR gives each word its box, and the numbers can be put back
      // under the header's columns. It only runs when there is a reason to
      // think a value was lost, because it is another OCR call over the same
      // photo and otherwise has nothing to add.
      if (scan.tees.any((t) => t.yards.length < 18) &&
          scan.tees.any((t) => t.yards.isNotEmpty)) {
        setState(() => scanStatus = 'Realigning the table columns…');
        final geomScan = await _geometryPass(file, scan);
        if (geomScan != null && geomScan.tees.isNotEmpty) {
          attempts.add(geomScan);
          scan = mergeScans(attempts);
        }
      }
      // The par row is the smallest print on the card, so it is the first
      // thing a poor photo loses while the yardage rows survive. One extra
      // pass restricted to digits recovers it, and only runs when the normal
      // passes found no par at all.
      List<int>? digitPars;
      if (scan.pars.length != 18 && scan.pars.length != 9) {
        setState(() => scanStatus = 'Reading the par row…');
        digitPars = await _parsFromDigitsPass(file, scan);
        if (digitPars != null) {
          scan = ScorecardScan(
            pars: digitPars,
            tees: scan.tees,
            rating: scan.rating,
            slope: scan.slope,
            hcp: scan.hcp,
            parSubtotals: const SubtotalCheck(
              front: true,
              back: null,
              total: true,
              printed: false,
            ),
          );
          texts.add(lastOcrDigitsText);
        }
      }
      if (!mounted) return;
      _applyScan(scan, file, bestText, texts);
    } on ScanException catch (e) {
      if (!mounted) return;
      setState(() => scanning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The hOCR pass: re-reads the photo asking for word boxes and places each
  /// tee box's yardages under the hole columns. Returns null when the
  /// platform has no hOCR or the pass found no table to align to, in which
  /// case the text read stands on its own.
  Future<ScorecardScan?> _geometryPass(
    XFile file,
    ScorecardScan textScan,
  ) async {
    try {
      final path = await preprocessScorecard(
        file.path,
        prep: ImagePrep.stretched,
      );
      final hocr = await extractScorecardHocr(path);
      if (hocr == null) return null;
      lastOcrHocrText = hocr;
      final geom = parseHocrGeometry(hocr, textScan: textScan);
      return geom.tees.isEmpty ? null : geom;
    } catch (_) {
      return null;
    }
  }

  /// One extra OCR pass restricted to digits, used only to recover the par
  /// row. Returns null when the pass yields no par row that adds up.
  ///
  /// Runs on the stretched image, which keeps the grey levels Tesseract
  /// needs: a binarized pass turns a thin digit into a shape it is happy to
  /// call a letter even with a whitelist.
  Future<List<int>?> _parsFromDigitsPass(XFile file, ScorecardScan scan) async {
    try {
      final path = await preprocessScorecard(
        file.path,
        prep: ImagePrep.stretched,
      );
      final text = await extractScorecardText(path, args: digitsOnlyArgs);
      if (text.trim().isEmpty) return null;
      lastOcrDigitsText = text;
      final total = printedParTotal(text);
      // The digits pass has no labels, so the par row is recognised by its
      // shape instead: a run of 18 values in 3..5. The printed total, when
      // the card gave one, is what makes a match certain — a run of single
      // digits that adds up to the total next to it is not a coincidence.
      for (final line in text.split('\n')) {
        final row = [
          for (final n in RegExp(
            r'\d+',
          ).allMatches(line).map((m) => int.parse(m.group(0)!)))
            if (n >= 3 && n <= 5) n,
        ];
        if (row.length != 18) continue;
        final sum = row.fold(0, (a, b) => a + b);
        if (total != null && sum != total) continue;
        if (total == null && sum < 54) continue;
        return row;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// True when a scan has nothing left worth another OCR pass: all three
  /// kinds of data the card carries, and nothing that failed validation.
  static bool _scanComplete(ScorecardScan s) {
    if (s.pars.length != 18 && s.pars.length != 9) return false;
    if (s.tees.isEmpty || s.tees.every((t) => t.yards.length < 18)) {
      return false;
    }
    if (!validStrokeIndexes(s.hcp, s.pars.length)) return false;
    if (s.parSubtotals.printed && !s.parSubtotals.ok) return false;
    return s.tees.every((t) => t.verified);
  }

  /// Prefills the form from a scan. OCR guesses — the user verifies
  /// everything before saving. The photo is kept and stored with the
  /// course on save so it can be viewed later.
  void _applyScan(
    ScorecardScan scan,
    XFile file,
    String rawText, [
    List<String> allTexts = const [],
  ]) {
    final filled = <String>[];
    List<int>? scannedPars;
    setState(() {
      scanning = false;
      scanPhoto = file;
      _photoZoom.reset();
      lastOcrText = rawText;
      lastOcrAttempts = List.of(allTexts);
      parUncertain = const {};
      parFromYardages = false;
      if (scan.pars.length == 18 || scan.pars.length == 9) {
        holesCount = scan.pars.length;
        scannedPars = List.of(scan.pars);
        filled.add('${scan.pars.length} pars');
      } else {
        // The digits pass already ran and came back empty, so par has to be
        // worked out from the yardages: the yardage rows are repeated once
        // per tee box and usually survive a photo that lost the par row. A
        // hole that is short from every tee box is a par 3 whatever the par
        // row said. Holes whose length cannot separate a par 4 from a par 5
        // are flagged for the user rather than guessed silently.
        final proposal = inferParFromYardages([
          for (final t in scan.tees)
            if (t.verified) t.yards,
        ], total: printedParTotal(rawText));
        if (proposal != null) {
          holesCount = 18;
          scannedPars = List.of(proposal.pars);
          parUncertain = proposal.uncertainHoles.toSet();
          parFromYardages = true;
          filled.add('par from yardages');
        }
      }
      if (scan.tees.isNotEmpty) {
        for (final t in tees) {
          t.dispose();
        }
        tees.clear();
        for (final st in scan.tees) {
          final d = _TeeDraft(st.name, holesCount);
          if (scannedPars != null) d.pars = List.of(scannedPars!);
          for (var i = 0; i < holesCount && i < st.yards.length; i++) {
            d.yards[i] = st.yards[i];
          }
          tees.add(d);
        }
        editYardsTee = 0;
        filled.add(
          '${scan.tees.length} tee${scan.tees.length == 1 ? '' : 's'}',
        );
      } else {
        for (final t in tees) {
          t.resize(holesCount);
          if (scannedPars != null) t.pars = List.of(scannedPars!);
        }
      }
      // Every tee box carries its own rating/slope on the card; fall back to
      // the card-wide value for the first tee only, since one rating cannot
      // describe five different tees.
      for (var i = 0; i < tees.length; i++) {
        final st = i < scan.tees.length ? scan.tees[i] : null;
        final d = tees[i];
        final r = st?.rating ?? (i == 0 ? scan.rating : null);
        final s = st?.slope ?? (i == 0 ? scan.slope : null);
        if (r != null && d.ratingCtrl.text.trim().isEmpty) {
          d.ratingCtrl.text = r.toString();
        }
        if (s != null && d.slopeCtrl.text.trim().isEmpty) {
          d.slopeCtrl.text = s.toString();
        }
      }
      if (tees.isNotEmpty) {
        if (tees.first.ratingCtrl.text.trim().isNotEmpty) filled.add('rating');
        if (tees.first.slopeCtrl.text.trim().isNotEmpty) filled.add('slope');
      }
      // Preserve the scanned handicap row only when it is a complete valid
      // permutation; missing or unreadable values remain blank for editing.
      if (validStrokeIndexes(scan.hcp, holesCount)) {
        for (final tee in tees) {
          tee.strokeIndexes = List<int?>.of(scan.hcp);
        }
        filled.add('handicap');
      }
    });
    // Say what the card itself confirms. A row that agrees with its printed
    // OUT/IN/TOT is far more trustworthy than one that does not, so the
    // user knows which tee boxes to re-read before saving.
    final notes = <String>[];
    if (scan.pars.isNotEmpty) {
      if (scan.parSubtotals.printed) {
        notes.add(
          scan.parSubtotals.ok
              ? 'par matches the printed totals'
              : 'par does NOT match the printed totals',
        );
      }
    }
    if (scan.tees.isNotEmpty) {
      final verified = scan.verifiedTees;
      if (verified > 0) {
        notes.add('$verified/${scan.tees.length} tees match printed totals');
      }
      final mismatched = [
        for (final t in scan.tees)
          if (t.parMismatch.isNotEmpty)
            '${t.name} hole ${t.parMismatch.join(",")}',
      ];
      if (mismatched.isNotEmpty) {
        notes.add('check yardage vs par on ${mismatched.join("; ")}');
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [
            if (filled.isEmpty)
              'Could not read a scorecard from that photo — try closer, straight-on, well-lit. The form is unchanged.'
            else
              'Scan filled in ${filled.join(', ')}. Check every value before saving.',
            if (notes.isNotEmpty) notes.join(' · '),
          ].join('\n'),
        ),
        duration: const Duration(seconds: 7),
      ),
    );
  }

  Future<void> _save() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the course a name first.')),
      );
      return;
    }
    final seenNames = <String>{};
    for (var ti = 0; ti < tees.length; ti++) {
      final t = tees[ti];
      final tName = t.nameCtrl.text.trim();
      if (tName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Name tee ${ti + 1} (e.g. Blue, White, Red).'),
          ),
        );
        return;
      }
      if (!seenNames.add(tName.toLowerCase())) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Two tees are both named "$tName".')),
        );
        return;
      }
      final rating = double.tryParse(t.ratingCtrl.text.trim());
      final slope = int.tryParse(t.slopeCtrl.text.trim());
      final teeHoles = t.pars.length;
      final minRating = teeHoles == 9 ? 20.0 : 45.0;
      final maxRating = teeHoles == 9 ? 45.0 : 90.0;
      if (rating == null || rating < minRating || rating > maxRating) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              teeHoles == 9
                  ? 'Enter the 9-hole course rating for "$tName" from the scorecard (20–45).'
                  : 'Enter the course rating for "$tName" from the scorecard (45–90).',
            ),
          ),
        );
        return;
      }
      if (slope == null || slope < 55 || slope > 155) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter the slope for "$tName" from the scorecard (55–155).',
            ),
          ),
        );
        return;
      }
      final enteredIndexes = <int>{};
      for (final index in t.strokeIndexes.whereType<int>()) {
        if (index < 1 || index > teeHoles) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Enter a valid HCP from 1 to $teeHoles for "$tName", or leave it blank.',
              ),
            ),
          );
          return;
        }
        if (!enteredIndexes.add(index)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'HCP $index is entered more than once for "$tName".',
              ),
            ),
          );
          return;
        }
      }
      if (teeHoles == 18) {
        for (final nine in [
          (
            label: 'Front 9',
            rating: t.frontNineRatingCtrl.text.trim(),
            slope: t.frontNineSlopeCtrl.text.trim(),
          ),
          (
            label: 'Back 9',
            rating: t.backNineRatingCtrl.text.trim(),
            slope: t.backNineSlopeCtrl.text.trim(),
          ),
        ]) {
          if (nine.rating.isEmpty && nine.slope.isEmpty) continue;
          final nineRating = double.tryParse(nine.rating);
          final nineSlope = int.tryParse(nine.slope);
          if (nineRating == null ||
              nineRating < 20 ||
              nineRating > 45 ||
              nineSlope == null ||
              nineSlope < 55 ||
              nineSlope > 155) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Enter both the ${nine.label} rating (20–45) and slope (55–155) for "$tName", or leave both blank.',
                ),
              ),
            );
            return;
          }
        }
      }
    }
    final id =
        widget.existing?.id ??
        widget.catalogCourse?.catalogCourseId ??
        'custom-${DateTime.now().microsecondsSinceEpoch}';
    String slug(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    String imagePath = keptPhoto;
    if (scanPhoto != null) {
      try {
        imagePath = await persistScanPhoto(scanPhoto!, id);
      } catch (_) {
        imagePath = keptPhoto;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      Course(
        id: id,
        name: name,
        city: cityCtrl.text.trim(),
        state: stateCtrl.text.trim(),
        tees: [
          for (var ti = 0; ti < tees.length; ti++)
            Tee(
              id: '$id-${slug(tees[ti].nameCtrl.text.trim())}-$ti',
              name: tees[ti].nameCtrl.text.trim(),
              rating: double.parse(tees[ti].ratingCtrl.text.trim()),
              slope: int.parse(tees[ti].slopeCtrl.text.trim()),
              frontNineRating: double.tryParse(
                tees[ti].frontNineRatingCtrl.text.trim(),
              ),
              frontNineSlope: int.tryParse(
                tees[ti].frontNineSlopeCtrl.text.trim(),
              ),
              backNineRating: double.tryParse(
                tees[ti].backNineRatingCtrl.text.trim(),
              ),
              backNineSlope: int.tryParse(
                tees[ti].backNineSlopeCtrl.text.trim(),
              ),
              holes: List.generate(tees[ti].pars.length, (i) {
                return HoleInfo(
                  number: i + 1,
                  par: tees[ti].pars[i],
                  yardage: tees[ti].yards[i],
                  strokeIndex: tees[ti].strokeIndexes[i],
                );
              }),
            ),
        ],
        custom: widget.existing?.custom ?? true,
        imagePath: imagePath,
        ocrText: lastOcrText,
        ocrAttempts: lastOcrAttempts,
      ),
    );
  }
}
