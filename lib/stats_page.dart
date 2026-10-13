
import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'models.dart';
import 'scan_service.dart';
import 'store.dart';
import 'whs.dart' as whs;
import 'post_page.dart';
import 'scorecard_widgets.dart';
import 'text_format.dart';

// ---------------- STATS ----------------
class StatsPage extends StatefulWidget {
  final GolfStore store;
  const StatsPage({super.key, required this.store});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  // 'course' groups alphabetically, 'date' by latest round, 'score' by best.
  String _sort = 'course';

  int? _courseHandicap(Round round) {
    if (round.courseHandicap != null) return round.courseHandicap;
    final tee = widget.store.teeById(round.courseId, round.teeId);
    if (tee == null) return null;
    // Backfilled from the live index when no earlier index exists (rounds
    // posted before any index, or all on the same day): the avatar shows
    // what the round carries under the current index.
    final index =
        round.handicapIndexAtPlay ??
        widget.store.handicapIndexBefore(round.playedAt) ??
        widget.store.handicapIndex;
    if (index == null) return null;
    final ch = tee.courseHandicapForRound(
      holesPlayed: round.holes.length,
      startHole: round.startHole,
      handicapIndex: index,
    );
    if (ch != null) return ch;
    // Nine holes on a tee without published nine-hole ratings: a nine-hole
    // tee's own rating covers nine directly, otherwise halve the full tee.
    if (round.holes.length == 9) {
      final full = whs.courseHandicap(
        handicapIndex: index,
        slopeRating: tee.slope.toDouble(),
        courseRating: tee.rating,
        par: tee.par,
      );
      return tee.holes.length == 9 ? full : (full / 2).round();
    }
    return null;
  }

  /// The course's own handicap for the live index, on the most recently
  /// played tee: HI × (slope ÷ 113) + (rating − par), rounded. A dash when
  /// the index or the tee cannot be resolved.
  String _headerCourseHandicap(String courseId, List<Round> rounds) {
    final store = widget.store;
    final hi = store.handicapIndex;
    final course = store.courseById(courseId);
    if (hi == null || course == null || course.tees.isEmpty) return '—';
    final ordered = rounds.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    Tee? tee;
    for (final round in ordered) {
      tee = store.teeById(round.courseId, round.teeId);
      if (tee != null) break;
    }
    tee ??= course.defaultTee;
    return '${whs.courseHandicap(handicapIndex: hi, slopeRating: tee.slope.toDouble(), courseRating: tee.rating, par: tee.par)}';
  }

  String _roundDate(DateTime date) {
    final local = date.toLocal();
    return '${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.year}';
  }

  /// Total for the front (holes 1-9) or back (10-18) as scorecard numbering
  /// goes, against the nine the round actually covers. A nine the round never
  /// touches shows a dash.
  String _nineScore(Round round, {required bool front}) {
    var total = 0;
    var seen = false;
    for (var i = 0; i < round.holes.length; i++) {
      final at = round.startHole + i;
      if (front ? at < 9 : at >= 9) {
        total += round.holes[i].score;
        seen = true;
      }
    }
    return seen ? '$total' : '—';
  }

  DateTime _latestPlayed(List<Round> rounds) =>
      rounds.map((r) => r.playedAt).reduce((a, b) => a.isAfter(b) ? a : b);

  int _bestTotal(List<Round> rounds) =>
      rounds.map((r) => r.totalGross).reduce((a, b) => a < b ? a : b);

  /// Rows newest-first, except score sort which leads with the best round.
  List<Round> _sortedRows(List<Round> rounds) {
    final out = rounds.toList();
    if (_sort == 'score') {
      out.sort((a, b) {
        final byScore = a.totalGross.compareTo(b.totalGross);
        return byScore != 0 ? byScore : b.playedAt.compareTo(a.playedAt);
      });
    } else {
      out.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    }
    return out;
  }

  /// One course's round rows. Date sort walks newest-first, so a year
  /// separator labels each block of rounds that falls into an older year.
  List<Widget> _roundRows(List<Round> rounds) {
    final children = <Widget>[];
    var lastYear = 0;
    for (final round in _sortedRows(rounds)) {
      final year = round.playedAt.year;
      if (_sort == 'date' && lastYear != 0 && year != lastYear) {
        children.add(_yearDivider(year));
      }
      lastYear = year;
      children.add(_roundCard(round));
    }
    return children;
  }

  Widget _yearDivider(int year) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Text(
          '$year',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ],
    ),
  );

  Widget _roundCard(Round round) => Card(
    key: ValueKey('stats-round-${round.id}'),
    margin: const EdgeInsets.only(top: 6),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListTile(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostPage(store: widget.store, existing: round),
          ),
        );
        if (mounted) setState(() {});
      },
      leading: Semantics(
        label:
            'Course handicap ${_courseHandicap(round) ?? 'not available'}',
        child: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primaryContainer,
          foregroundColor: Theme.of(
            context,
          ).colorScheme.onPrimaryContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CH',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_courseHandicap(round) ?? '—'}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      title: Text(
        'Total: ${round.totalGross} • '
        '(F) ${_nineScore(round, front: true)} • '
        '(B) ${_nineScore(round, front: false)}',
      ),
      subtitle: Text(
        '${_roundDate(round.playedAt)} • '
        '${round.holes.length} holes • '
        'Putts ${round.totalPutts} • '
        'Pen ${round.totalPenalties}',
      ),
      trailing: photoUsable(round.imagePath)
          ? IconButton(
              key: ValueKey('stats-round-photo-${round.id}'),
              icon: const Icon(Icons.photo_outlined),
              tooltip: 'View scorecard photo',
              onPressed: () => showCoursePhoto(
                context,
                widget.store.courseById(round.courseId)?.name ?? 'Round',
                round.imagePath,
              ),
            )
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final s = store.statSummary();
    final roundsByCourse = <String, List<Round>>{};
    for (final round in store.rounds) {
      roundsByCourse.putIfAbsent(round.courseId, () => []).add(round);
    }
    String groupName(String id) =>
        store.courseById(id)?.name.toLowerCase() ?? id.toLowerCase();
    final courseIds = roundsByCourse.keys.toList()
      ..sort((left, right) {
        switch (_sort) {
          case 'date':
            final byDate = _latestPlayed(
              roundsByCourse[right]!,
            ).compareTo(_latestPlayed(roundsByCourse[left]!));
            return byDate != 0
                ? byDate
                : groupName(left).compareTo(groupName(right));
          case 'score':
            final byScore = _bestTotal(
              roundsByCourse[left]!,
            ).compareTo(_bestTotal(roundsByCourse[right]!));
            return byScore != 0
                ? byScore
                : groupName(left).compareTo(groupName(right));
          default:
            return groupName(left).compareTo(groupName(right));
        }
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (s.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Post a round to see FIR, GIR, putts and penalties.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (s.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _stat(context, 'FIR %', s['FIR']!),
                _stat(context, 'GIR %', s['GIR']!),
                _stat(context, 'Putts/hole', s['Putts/Hole']!),
                _stat(context, 'Pen/round', s['Pen/Round']!),
              ],
            ),
          const SizedBox(height: 24),
          Text(
            'Courses Played',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const ValueKey('stats-sort'),
            initialValue: _sort,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sort by'),
            items: const [
              DropdownMenuItem(value: 'course', child: Text('Course')),
              DropdownMenuItem(value: 'date', child: Text('Date')),
              DropdownMenuItem(value: 'score', child: Text('Score')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? 'course'),
          ),
          const SizedBox(height: 8),
          for (final courseId in courseIds)
            Card(
              key: ValueKey('stats-course-$courseId'),
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: PageStorageKey('stats-course-expansion-$courseId'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Text(
                  store.courseById(courseId)?.name ?? 'Unknown course',
                  style: AppType.title,
                ),
                subtitle: Text(
                  [
                    plural(roundsByCourse[courseId]!.length, 'round'),
                    'CH ${_headerCourseHandicap(courseId, roundsByCourse[courseId]!)}',
                  ].join(' • '),
                ),
                trailing: const Icon(Icons.keyboard_arrow_down),
                children: _roundRows(roundsByCourse[courseId]!),
              ),
            ),
          const SizedBox(height: 20),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Version ${appVersion.split('+').first}',
                key: const ValueKey('stats-app-version'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String k, double v) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              k,
              style: AppType.meta.copyWith(color: scheme.onSurfaceVariant),
            ),
            Text(
              v.toStringAsFixed(1),
              style: AppType.title.copyWith(fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}
