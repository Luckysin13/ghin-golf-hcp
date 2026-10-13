import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'design_tokens.dart';
import 'models.dart';
import 'score_entry.dart';
import 'scan_service.dart';
import 'photo_source_sheet.dart';
import 'playing_handicap_panel.dart';
import 'store.dart';
import 'score_widgets.dart';
import 'scorecard_widgets.dart';

class PostPage extends StatefulWidget {
  final GolfStore store;

  /// When set, the page corrects this round instead of posting a new one:
  /// the scores start where they were and saving overwrites the original.
  final Round? existing;
  const PostPage({super.key, required this.store, this.existing});
  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  String? courseId;
  String? teeId;
  int holesCount = 18;
  int startHole = 0; // 0 = front nine, 9 = back nine
  bool incompleteRoundReasonValid = false;
  late DateTime playedAt;
  late List<HoleScore> holes;
  int sel = 0; // hole being edited (quick entry)
  String _photoPath = '';
  // A scorecard picture taken mid-round, persisted once the round is saved.
  XFile? _pendingPhoto;
  // Playing Conditions Calculation adjustment already applied by the venue to
  // this round. Null-player/direct-entry screens can leave it at 0.0.
  double _pcc = 0.0;
  final _stripCtrl = ScrollController();
  final _pageCtrl = ScrollController();
  double _stripW = 0;

  @override
  void dispose() {
    _stripCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Keeps the selected hole chip centered in the strip after it moves.
  void _centerSelSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stripCtrl.hasClients || holes.isEmpty || _stripW <= 0) return;
      const itemW = 60.0; // 54 chip + 6 separator
      final x = sel * itemW + itemW / 2 - _stripW / 2;
      _stripCtrl.animateTo(
        x.clamp(0.0, _stripCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _selectHole(int i) {
    setState(() => sel = i.clamp(0, holes.length - 1));
    _centerSelSoon();
  }

  /// Typed entry for scores past triple, via the hole header.
  Future<void> _editHoleScore(int i) async {
    final entered = await showDialog<int>(
      context: context,
      builder: (_) => HoleScoreDialog(
        holeNumber: i + 1,
        par: _parAt(i, _tee()),
        currentScore: holes[i].score,
      ),
    );
    if (entered == null || !mounted) return;
    _setScore(i, entered);
  }

  Future<void> _pickRoundDate() async {
    final initialDate = DateUtils.dateOnly(playedAt.toLocal());
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: initialDate.isBefore(DateTime(1900))
          ? initialDate
          : DateTime(1900),
      lastDate: initialDate.isAfter(today) ? initialDate : today,
    );
    if (picked == null || !mounted) return;

    final previousLocal = playedAt.toLocal();
    setState(() {
      playedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        previousLocal.hour,
        previousLocal.minute,
        previousLocal.second,
        previousLocal.millisecond,
        previousLocal.microsecond,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    playedAt = existing?.playedAt ?? DateTime.now();
    _photoPath = existing?.imagePath ?? '';
    _pcc = existing?.pcc ?? 0.0;
    if (existing != null) {
      courseId = existing.courseId;
      teeId = existing.teeId;
      startHole = existing.startHole;
      incompleteRoundReasonValid = existing.incompleteRoundReasonValid;
      // Copied, so abandoning the edit leaves the stored round alone.
      holes = existing.holes.map((h) => h.copy()).toList();
      holesCount = holes.length;
      sel = 0;
      return;
    }
    if (widget.store.courses.isNotEmpty) {
      final firstCourse = widget.store.alphabeticalCourses.first;
      courseId = firstCourse.id;
      teeId = firstCourse.defaultTee.id;
      holes = List.generate(18, (i) => HoleScore(score: _parFor(i)));
    } else {
      holes = [];
    }
  }

  int _parFor(int i) {
    final t = _tee();
    if (t == null) return 4;
    final idx = startHole + i;
    if (idx < 0 || idx >= t.holes.length) return 4;
    return t.holes[idx].par;
  }

  Tee? _tee() => (courseId == null || teeId == null)
      ? null
      : widget.store.teeById(courseId!, teeId!);

  /// Unrounded Course Handicap for the current selection, using the live
  /// Handicap Index (the number a player plans their round against). Null
  /// until a Handicap Index exists or the tee cannot rate the selection.
  double? unroundedChForPanel(Tee? tee) {
    final index = widget.store.handicapIndex;
    if (tee == null || index == null) return null;
    return tee.unroundedCourseHandicapForRound(
      holesPlayed: holesCount,
      startHole: startHole,
      handicapIndex: index,
    );
  }

  void _resetScores() {
    setState(() {
      incompleteRoundReasonValid = false;
      holes = List.generate(holesCount, (i) => HoleScore(score: _parFor(i)));
      sel = 0;
    });
  }

  int _parAt(int i, Tee? tee) {
    if (tee == null) return 4;
    final idx = startHole + i;
    if (idx < 0 || idx >= tee.holes.length) return 4;
    return tee.holes[idx].par;
  }

  /// Score-vs-par color scale, shared by the hole strip and score entry.
  /// User-editable on Post Score (palette icon), persisted in store.
  Color _diffColor(int d) => Color(widget.store.scoreColorValue(d));

  Color _scoreColor(BuildContext context, int score, int par) =>
      _diffColor(score - par);

  TextStyle _choiceLabelStyle(BuildContext context, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return TextStyle(
      color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
    );
  }

  void _setScore(int i, int score, {bool advance = false}) {
    setState(() {
      holes[i].score = score.clamp(1, 12);
      holes[i].sanitize();
      if (advance && i + 1 < holes.length) sel = i + 1;
    });
    _centerSelSoon();
  }

  @override
  Widget build(BuildContext context) {
    final courses = widget.store.alphabeticalCourses;
    if (courses.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Post Score')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No courses yet. Go to Courses tab and add your local course first.',
            ),
          ),
        ),
      );
    }
    // The course/tee fallbacks below rebuild `holes` from par, which would wipe
    // the very scores an edit was opened to correct. So a round being edited
    // keeps its scores, and is only repointed if its course is really gone.
    final editing = widget.existing != null;
    if (courseId == null || !courses.any((c) => c.id == courseId)) {
      courseId = courses.first.id;
      teeId = courses.first.defaultTee.id;
      if (!editing) {
        holes = List.generate(holesCount, (i) => HoleScore(score: _parFor(i)));
      }
    }
    final course = courses.firstWhere(
      (c) => c.id == courseId,
      orElse: () => courses.first,
    );
    if (teeId == null || !course.tees.any((t) => t.id == teeId)) {
      teeId = course.defaultTee.id;
      if (!editing) {
        holes = List.generate(holesCount, (i) => HoleScore(score: _parFor(i)));
      }
    }
    final tee = _tee();
    final holeCountTee =
        tee ??
        course.tees.firstWhere(
          (t) => t.id == teeId,
          orElse: () => course.defaultTee,
        );
    // The dropdown must contain the current count: a legacy partial round
    // keeps its own count in the edit form, while a fresh card clamps to a
    // supported count (preferring 18) and rebuilds its scores from par.
    var holeOptions = holeCountOptionsForTee(holeCountTee.holes.length);
    if (editing && !holeOptions.contains(holesCount)) {
      holeOptions = [...holeOptions, holesCount]..sort();
    }
    if (!editing && !holeOptions.contains(holesCount)) {
      holesCount = holeOptions.last;
      holes = List.generate(holesCount, (i) => HoleScore(score: _parFor(i)));
    }
    if (sel >= holes.length) sel = holes.isEmpty ? 0 : holes.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit Round' : 'Post Score'),
        actions: [
          IconButton(
            tooltip: 'Score colors',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => showScoreColorsDialog(context, widget.store),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('play-page-list'),
        controller: _pageCtrl,
        padding: const EdgeInsets.all(Insets.gutter),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: courseId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: [
                      for (final c in courses)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() {
                      courseId = v!;
                      final nc = courses.firstWhere((c) => c.id == v);
                      teeId = nc.defaultTee.id;
                      holesCount = nc.defaultTee.holes.length == 18 ? 18 : 9;
                      startHole = 0;
                      _resetScores();
                    }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: teeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Teebox'),
                    items: [
                      for (final t in course.tees)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            '${t.name} • ${t.rating}/${t.slope} • Par ${t.par}',
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final selectedTee = course.tees.firstWhere(
                        (t) => t.id == v,
                      );
                      setState(() {
                        teeId = v;
                        if (!holeCountOptionsForTee(
                          selectedTee.holes.length,
                        ).contains(holesCount)) {
                          holesCount = selectedTee.holes.length == 18 ? 18 : 9;
                        }
                        startHole = 0;
                        _resetScores();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('play-hole-count-selector'),
                    initialValue: holesCount,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Holes'),
                    items: [
                      for (final n in holeOptions)
                        DropdownMenuItem(value: n, child: Text('$n Holes')),
                    ],
                    onChanged: (n) {
                      if (n == null) return;
                      setState(() {
                        holesCount = n;
                        startHole = 0;
                        _resetScores();
                      });
                    },
                  ),
                  if (editing) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      key: const ValueKey('edit-round-date'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Round date'),
                      subtitle: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(playedAt.toLocal()),
                      ),
                      trailing: TextButton.icon(
                        onPressed: _pickRoundDate,
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Change'),
                      ),
                    ),
                  ],
                  if (holesCount >= 10 && holesCount < 18)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: incompleteRoundReasonValid,
                      title: const Text(
                        'I had a valid reason for not completing the round',
                      ),
                      onChanged: (value) => setState(
                        () => incompleteRoundReasonValid = value ?? false,
                      ),
                    ),
                  if (holesCount == 9) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Front 9')),
                        ButtonSegment(value: 9, label: Text('Back 9')),
                      ],
                      selected: {startHole},
                      onSelectionChanged: (s) => setState(() {
                        startHole = s.first;
                        _resetScores();
                      }),
                    ),
                  ],
                  const SizedBox(height: 8),
                  DropdownButtonFormField<double>(
                    key: const ValueKey('play-pcc-selector'),
                    initialValue: _pcc,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'PCC (venue adjustment)',
                    ),
                    items: [
                      for (final value in pccOptions)
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            value == 0.0
                                ? 'None'
                                : '${value >= 0 ? "+" : ""}${value.toStringAsFixed(1)}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _pcc = v ?? 0.0),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (ctx, cons) {
              _stripW = cons.maxWidth;
              return SizedBox(
                height: 78,
                child: ListView.separated(
                  controller: _stripCtrl,
                  scrollDirection: Axis.horizontal,
                  itemCount: holes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final par = _parAt(i, tee);
                    final active = i == sel;
                    final col = _scoreColor(context, holes[i].score, par);
                    final scheme = Theme.of(ctx).colorScheme;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selectHole(i),
                      child: Container(
                        key: ValueKey('play-hole-chip-$i'),
                        width: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: active
                              ? Border.all(color: scheme.primary, width: 3)
                              : Border.all(color: scheme.outlineVariant),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: scheme.primary.withValues(
                                      alpha: 0.24,
                                    ),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  key: ValueKey('play-hole-number-$i'),
                                  width: double.infinity,
                                  color: scheme.primaryContainer,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  key: ValueKey('play-hole-score-$i'),
                                  width: double.infinity,
                                  color: col,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${holes[i].score}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: readableOn(col),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          if (holes.isNotEmpty) const SizedBox(height: Insets.md),
          if (holes.isNotEmpty) _quickEditor(sel, tee),
          if (editing) ...[
            const SizedBox(height: Insets.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: photoUsable(_photoPath)
                    ? Row(
                        children: [
                          InkWell(
                            onTap: () => showCoursePhoto(
                              context,
                              course.name,
                              _photoPath,
                            ),
                            child: _roundPhotoThumb(_photoPath),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Scorecard photo attached'),
                          ),
                          TextButton.icon(
                            key: const ValueKey('edit-round-remove-photo'),
                            onPressed: _removeRoundPhoto,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Remove'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Expanded(child: Text('No scorecard photo')),
                          OutlinedButton.icon(
                            key: const ValueKey('edit-round-add-photo'),
                            onPressed: _pickRoundPhoto,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('Save Scorecard'),
                          ),
                        ],
                      ),
              ),
            ),
          ],
          if (!editing) ...[
            const SizedBox(height: Insets.md),
            OutlinedButton.icon(
              key: const ValueKey('play-save-scorecard'),
              onPressed: _pickPlayPhoto,
              icon: Icon(
                _pendingPhoto == null
                    ? Icons.add_a_photo_outlined
                    : Icons.check_circle_outline,
              ),
              label: Text(
                _pendingPhoto == null ? 'Save Scorecard' : 'Attached',
              ),
            ),
            const SizedBox(height: Insets.md),
          ],
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(
              editing
                  ? 'Update ${holes.fold(0, (s, h) => s + h.score)} total'
                  : 'Save ${holes.fold(0, (s, h) => s + h.score)} total',
            ),
            onPressed: _save,
          ),
          const SizedBox(height: Insets.md),
          PlayingHandicapPanel(
            unroundedCourseHandicap: unroundedChForPanel(tee),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, Widget controls) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 84,
        child: Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
      Expanded(
        child: Padding(
          key: ValueKey('play-controls-${label.toLowerCase()}'),
          padding: const EdgeInsets.only(right: Insets.lg),
          child: Align(alignment: Alignment.centerLeft, child: controls),
        ),
      ),
    ],
  );

  /// Compact stepper controls, kept together in the right-hand column.
  Widget _statStepper({
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        outlineStep(context, Icons.remove, onMinus),
        SizedBox(
          width: 36,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        outlineStep(context, Icons.add, onPlus),
      ],
    );
  }

  /// One hole on screen: one-tap score vs par (auto-advances), then
  /// putts/fairway/penalties/drive only if you want them.
  Widget _quickEditor(int i, Tee? tee) {
    final h = holes[i];
    final par = _parAt(i, tee);
    const quick = [
      (-2, 'Eagle'),
      (-1, 'Birdie'),
      (0, 'Par'),
      (1, 'Bogey'),
      (2, 'Double'),
      (3, 'Triple'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(
                  key: const ValueKey('play-prev-hole'),
                  onPressed: i > 0 ? () => _selectHole(i - 1) : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text('< Prev'),
                ),
                Expanded(
                  child: InkWell(
                    key: const ValueKey('play-hole-header'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _editHoleScore(i),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Hole ${i + 1}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: ' • Par $par',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('play-next-hole'),
                  onPressed: i + 1 < holes.length
                      ? () => _selectHole(i + 1)
                      : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text('Next >'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Fixed three-per-row grid: every pill stretches to the same
            // width instead of shrink-wrapping its label.
            Column(
              children: [
                for (var r = 0; r < quick.length; r += 3)
                  Padding(
                    padding: EdgeInsets.only(top: r == 0 ? 0 : 6),
                    child: Row(
                      children: [
                        for (final (c, (d, label))
                            in quick.skip(r).take(3).indexed) ...[
                          if (c > 0) const SizedBox(width: 6),
                          Expanded(
                            child: ScorePill(
                              label: label,
                              selected: h.score == (par + d).clamp(1, 12),
                              color: _diffColor(d),
                              onTap: () => _setScore(i, par + d, advance: true),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            // Breathe the same amount below the pills as above them.
            const SizedBox(height: 8),
            const Divider(),
            _statRow(
              'GIR',
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: Text(
                      'Yes',
                      style: _choiceLabelStyle(context, h.gir),
                    ),
                    selected: h.gir,
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    onSelected: (_) => setState(() => h.gir = true),
                  ),
                  ChoiceChip(
                    label: Text(
                      'No',
                      style: _choiceLabelStyle(context, !h.gir),
                    ),
                    selected: !h.gir,
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    onSelected: (_) => setState(() => h.gir = false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _statRow(
              'Putts',
              _statStepper(
                value: '${h.putts}',
                onMinus: () => setState(() {
                  h.putts = (h.putts - 1).clamp(0, 5);
                  h.sanitize();
                }),
                onPlus: () => setState(() {
                  // Putts never reach the total: one stroke got here.
                  h.putts = (h.putts + 1).clamp(0, (h.score - 1).clamp(0, 5));
                  h.sanitize();
                }),
              ),
            ),
            const SizedBox(height: 8),
            _statRow(
              'Penalty',
              _statStepper(
                value: '${h.penalties}',
                onMinus: () => setState(() {
                  h.penalties = (h.penalties - 1).clamp(0, 4);
                  h.sanitize();
                }),
                onPlus: () => setState(() {
                  h.penalties = (h.penalties + 1).clamp(0, 4);
                  h.sanitize();
                  if (h.score < h.penalties + 1) h.score = h.penalties + 1;
                }),
              ),
            ),
            const SizedBox(height: 8),
            _statRow(
              'Fairway',
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final f in ['L', 'H', 'R'])
                    ChoiceChip(
                      label: Text(
                        f,
                        style: _choiceLabelStyle(context, h.fairway == f),
                      ),
                      selected: h.fairway == f,
                      selectedColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      onSelected: (_) =>
                          setState(() => h.fairway = h.fairway == f ? 'NA' : f),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundPhotoThumb(String path) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 56,
      height: 56,
      child: kIsWeb
          ? Image.network(path, fit: BoxFit.cover)
          : Image.file(File(path), fit: BoxFit.cover),
    ),
  );

  Future<void> _pickRoundPhoto() async {
    final existing = widget.existing;
    if (existing == null) return;
    final result = await pickScorecardPhoto(
      context,
      showRemove: _photoPath.isNotEmpty,
    );
    switch (result) {
      case null:
        return;
      case PhotoRemoved():
        await _removeRoundPhoto();
      case PhotoPicked(:final file):
        final path = await persistRoundPhoto(file, existing.id);
        if (!mounted) return;
        setState(() => _photoPath = path);
    }
  }

  Future<void> _removeRoundPhoto() async {
    final old = _photoPath;
    setState(() => _photoPath = '');
    await deleteScanPhoto(old);
  }

  Future<void> _pickPlayPhoto() async {
    final result = await pickScorecardPhoto(
      context,
      showRemove: _pendingPhoto != null,
    );
    switch (result) {
      case null:
        return;
      case PhotoRemoved():
        setState(() => _pendingPhoto = null);
      case PhotoPicked(:final file):
        setState(() => _pendingPhoto = file);
    }
  }

  Future<void> _save() async {
    final tee = _tee();
    if (tee == null || courseId == null || teeId == null) return;
    if (startHole + holes.length > tee.holes.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This tee only has ${tee.holes.length} holes, so it cannot hold ${holes.length}.',
          ),
        ),
      );
      return;
    }
    for (final h in holes) {
      h.sanitize();
    }
    // A round being edited keeps its historical handicap snapshot. New rounds
    // use the index in effect before this calendar day, since revisions happen
    // after play for the day is complete.
    final existing = widget.existing;
    final hi = existing != null
        ? existing.handicapIndexAtPlay
        : widget.store.handicapIndexBefore(playedAt);
    final ch = hi == null
        ? existing?.courseHandicap
        : tee.courseHandicapForRound(
                holesPlayed: holes.length,
                startHole: startHole,
                handicapIndex: hi,
              ) ??
              existing?.courseHandicap;
    // Posting caps (net double bogey, or par + 5 while establishing) apply
    // to the stored card; live entry keeps the actual scores until now.
    final adjustment = adjustScoresForPosting(
      handicapIndex: hi,
      courseHandicap: ch ?? 0,
      holes: [
        for (var i = 0; i < holes.length; i++)
          (
            par: tee.holes[startHole + i].par,
            // A hole with no published index ranks below every ranked hole.
            strokeIndex: tee.holes[startHole + i].strokeIndex ?? 19,
            grossScore: holes[i].score,
          ),
      ],
    );
    for (var i = 0; i < holes.length; i++) {
      holes[i].score = adjustment.holes[i].adjustedScore;
      holes[i].sanitize();
    }
    final id = existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    var imagePath = _photoPath;
    final pending = existing == null ? _pendingPhoto : null;
    if (pending != null) {
      try {
        imagePath = await persistRoundPhoto(pending, id);
      } catch (_) {
        // The round matters more than its picture.
      }
      if (!mounted) return;
    }
    final r = Round(
      // An edit keeps the round identity and playing-handicap snapshot, while
      // allowing the recorded play date to be corrected.
      id: id,
      courseId: courseId!,
      teeId: teeId!,
      playedAt: playedAt,
      format: existing?.format ?? 'stroke',
      isTournament: existing?.isTournament ?? false,
      holes: holes,
      pcc: _pcc,
      incompleteRoundReasonValid: incompleteRoundReasonValid,
      courseHandicap: ch,
      handicapIndexAtPlay: hi,
      startHole: startHole,
      imagePath: imagePath,
    );
    if (existing != null) {
      widget.store.updateRound(r);
    } else {
      widget.store.addRound(r);
    }
    final capped = adjustment.cappedCount;
    final cappedNote = capped == 0
        ? ''
        : ' $capped ${capped == 1 ? 'hole' : 'holes'} capped at max.';
    final verb = existing != null ? 'Updated' : 'Saved';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$verb ${r.totalGross} (CH ${ch ?? '—'}) — '
          '${selectionLabel(holes.length, startHole)}.$cappedNote',
        ),
      ),
    );
    if (existing != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      // Fresh card for the next round: same course, scores back to par,
      // hole 1 selected and scrolled into view.
      _pendingPhoto = null;
      _resetScores();
      _centerSelSoon();
      if (_pageCtrl.hasClients) {
        _pageCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }
}
