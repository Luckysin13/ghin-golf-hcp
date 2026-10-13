import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'csv_import.dart';
import 'design_tokens.dart';
import 'ghin_brand_mark.dart';
import 'handicap_card.dart';
import 'recent_rounds_section.dart';
import 'models.dart';
import 'quick_post.dart';
import 'scan_service.dart';
import 'export.dart';
import 'export_io.dart';
import 'store.dart';
import 'theme_toggle.dart';
import 'post_page.dart';
import 'courses_page.dart';
import 'stats_page.dart';
import 'text_format.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = GolfStore()..appVersion = appVersion;
  await store.load();
  runApp(GhinApp(store: store));
}

class GhinApp extends StatelessWidget {
  final GolfStore store;
  const GhinApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'GHIN HCP',
        theme: AppTheme.active(Brightness.light),
        darkTheme: AppTheme.active(Brightness.dark),
        themeMode: store.themeMode,
        home: RootTabs(store: store),
      ),
    );
  }
}

class RootTabs extends StatefulWidget {
  final GolfStore store;
  const RootTabs({super.key, required this.store});
  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(store: widget.store),
      PostPage(store: widget.store),
      CoursesPage(store: widget.store),
      StatsPage(store: widget.store),
    ];
    return Scaffold(
      body: IndexedStack(index: idx, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_golf_outlined),
            selectedIcon: Icon(Icons.sports_golf),
            label: 'Play',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Courses',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}

// ---------------- HOME ----------------
class HomePage extends StatelessWidget {
  final GolfStore store;
  const HomePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final hi = store.handicapIndex;
    final rounds = List<Round>.from(store.rounds)
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final pending = rounds.where((r) => r.pendingSync).length;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const GhinBrandMark(key: ValueKey('ghin-brand-mark')),
            const SizedBox(width: Insets.sm),
            const Flexible(
              child: Text(
                'GHIN HCP',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // In the app bar rather than at the foot of the page: the quick-post
        // card is tall, so a button below the recent rounds would sit off
        // screen on the first tap and a backup nobody finds is no backup.
        // Export and import sit together because they are two halves of one
        // job, and the way back in is the whole point of having a backup.
        actions: [
          ThemeModeButton(store: store),
          PopupMenuButton<String>(
            tooltip: 'Backup',
            icon: const Icon(Icons.save_alt),
            onSelected: (v) {
              if (v == 'csv' || v == 'json') {
                _runExport(context, store, v);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('Export CSV'),
                  subtitle: Text('One row per round, for a spreadsheet'),
                ),
              ),
              const PopupMenuItem(
                value: 'json',
                child: ListTile(
                  leading: Icon(Icons.archive),
                  title: Text('Export full backup'),
                  subtitle: Text(
                    'Everything: rounds, courses, settings, photos',
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('Import backup'),
                  subtitle: Text('Restore a JSON backup'),
                ),
                onTap: () => _runImport(context, store),
              ),
              PopupMenuItem(
                value: 'import-csv',
                child: ListTile(
                  leading: Icon(Icons.table_view),
                  title: Text('Import CSV'),
                  subtitle: Text('Bring rounds in from a spreadsheet'),
                ),
                onTap: () => _runImportCsv(context, store),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Insets.gutter),
        children: [
          HandicapCard(index: hi, roundCount: rounds.length, pending: pending),
          const SizedBox(height: Insets.md),
          QuickPostCard(store: store),
          const SizedBox(height: Insets.md),
          RecentRoundsSection(
            rows: recentRows(store, rounds),
            onEdit: (r) => _editRound(context, store, r),
            onDelete: (r) => _deleteRound(context, store, r),
          ),
        ],
      ),
    );
  }
}

/// Opens a posted round for correction.
void _editRound(BuildContext context, GolfStore store, Round r) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PostPage(store: store, existing: r),
    ),
  );
}

/// Deletes a round and gives four seconds to bring it back: a delete on a
/// phone is one mis-tap away from losing a round for good, so the toast's
/// 4s window is the safety net. Only an actual dismissal finalizes the
/// delete (and the scorecard photo goes with it); Undo keeps everything.
void _deleteRound(BuildContext context, GolfStore store, Round r) {
  final messenger = ScaffoldMessenger.of(context);
  final removed = store.deleteRound(r.id);
  if (removed == null) return;
  messenger.hideCurrentSnackBar();
  final photoPath = removed.round.imagePath;
  messenger
      .showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${courseName(store, removed.round)} • ${removed.round.totalGross}',
          ),
          duration: const Duration(seconds: 4),
          // A snackbar with an action defaults to `persist` in recent Flutter
          // versions, which pins it on screen forever instead of timing out.
          // The undo toast must be the exception: 4 seconds to undo, then it
          // goes away and the delete is final.
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restoreRound(removed.round, removed.index),
          ),
        ),
      )
      .closed
      .then((reason) {
        // Undo keeps the round, so it keeps the photo; any other dismissal
        // finalizes the delete and the orphaned file goes with it.
        if (reason != SnackBarClosedReason.action && photoPath.isNotEmpty) {
          deleteScanPhoto(photoPath);
        }
      });
}

/// Backup of the posted rounds.
///
/// Two formats because they answer different needs: CSV is for reading the
/// history in a spreadsheet, JSON carries the custom courses and score colors
/// too, so it is the one worth keeping if the phone is lost. Only JSON can be
/// imported back.
Future<void> _runExport(
  BuildContext context,
  GolfStore store,
  String format,
) async {
  final isCsv = format == 'csv';
  final messenger = ScaffoldMessenger.of(context);
  final at = DateTime.now();
  final result = await writeBackupFile(
    // The timestamp is the suggested name, so accepting the dialog as-is
    // still gives a name worth keeping, and a second export an hour later
    // does not overwrite the first.
    backupFilename(isCsv ? 'csv' : 'json', at: at),
    isCsv ? store.exportRoundsCsv() : store.exportRoundsJson(),
    mimeType: isCsv ? 'text/csv' : 'application/json',
  );
  final message = switch (result) {
    // Backing out of the save dialog is not an error, so say nothing.
    BackupCancelled() => null,
    BackupFailed(:final reason) => 'Export failed: $reason',
    // Only the file name: a full path does not fit in a snackbar, and the
    // user just chose the location anyway.
    BackupWritten(:final where) => 'Saved $where',
  };
  if (message == null) return;
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
  );
}

/// Restores a JSON backup.
///
/// Nothing is written to the store until the whole file has parsed, so a
/// truncated or unrelated file leaves the history exactly as it was. What
/// would be added is confirmed first, because an import is the one action
/// here that can add a lot of rounds at once and it should never be the
/// thing the user does by reflex.
Future<void> _runImport(BuildContext context, GolfStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  final String text;
  try {
    final picked = await pickBackupFile();
    if (picked == null) return; // cancelled
    text = picked;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That file could not be opened.')),
    );
    return;
  }

  Backup backup;
  try {
    backup = parseBackup(text);
  } on BackupFormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That file is not a ghin-golf backup.')),
    );
    return;
  }

  if (!context.mounted) return;
  // Ask whether there is anything here of the *whole* backup. Checking rounds
  // alone used to report "nothing new" and stop, throwing away courses,
  // colors and photos that the app was actually missing.
  final p = store.previewBackup(backup);
  final nothingNew =
      p.roundsAdded == 0 &&
      p.coursesAdded == 0 &&
      p.colorsChanged == 0 &&
      p.photosRestored == 0 &&
      !p.themeChanged;
  if (nothingNew && backup.rounds.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(_nothingNewMessage(backup, p))),
    );
    return;
  }

  if (!context.mounted) return;
  final RoundImportMode? roundsMode;
  if (backup.rounds.isNotEmpty) {
    roundsMode = await showDialog<RoundImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          '${_restoreSummary(p)}\n\n'
          'Merge keeps saved rounds and adds missing rounds. '
          'Overwrite replaces all saved rounds with the rounds in this file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, RoundImportMode.overwrite),
            child: const Text('Overwrite saved rounds'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, RoundImportMode.merge),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (roundsMode == null) return;
  } else {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(_restoreSummary(p)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    roundsMode = RoundImportMode.merge;
  }

  final r = await store.importBackup(backup, roundsMode: roundsMode);
  final done = <String>[
    if (r.added > 0) plural(r.added, 'round'),
    if (r.coursesAdded > 0) plural(r.coursesAdded, 'course'),
    if (r.photosRestored > 0) plural(r.photosRestored, 'photo'),
  ];
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        done.isEmpty
            ? 'Nothing in that backup was missing.'
            : 'Restored ${done.join(', ')}'
                  '${r.skipped > 0 ? ', ${r.skipped} already present' : ''}.',
      ),
    ),
  );
}

Future<void> _runImportCsv(BuildContext context, GolfStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  final String text;
  try {
    final picked = await pickBackupFile(kind: BackupKind.csv);
    if (picked == null) return; // cancelled
    text = picked;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That file could not be opened.')),
    );
    return;
  }

  List<CsvRound> rows;
  try {
    rows = parseCsv(text);
  } on CsvFormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That file is not a ghin-golf CSV.')),
    );
    return;
  }

  if (!context.mounted) return;
  final p = store.previewCsv(rows);
  final overwritePreview = store.previewCsv(
    rows,
    roundsMode: RoundImportMode.overwrite,
  );

  if (!context.mounted) return;
  final roundsMode = await showDialog<RoundImportMode>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Import CSV?'),
      content: Text(
        '${_csvSummary(p)}\n\n'
        'Merge keeps saved rounds and adds missing rounds. '
        'Overwrite replaces all saved rounds with '
        '${plural(overwritePreview.roundsAdded, 'round')} from this file.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, RoundImportMode.overwrite),
          child: const Text('Overwrite saved rounds'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, RoundImportMode.merge),
          child: const Text('Merge'),
        ),
      ],
    ),
  );
  if (roundsMode == null) return;

  final r = store.importCsv(rows, roundsMode: roundsMode);
  final done = <String>[
    if (r.added > 0) plural(r.added, 'round'),
    if (r.coursesAdded > 0) plural(r.coursesAdded, 'new course'),
  ];
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        done.isEmpty
            ? 'Nothing in that file was missing.'
            : 'Imported ${done.join(', ')}'
                  '${r.skipped > 0 ? ', ${r.skipped} already posted' : ''}.',
      ),
      // A reconstructed course is a stand-in built from a row's par total, not
      // the real layout, and the user needs to know which courses those are
      // before they start trusting their differentials.
      duration: r.coursesAdded > 0
          ? const Duration(seconds: 8)
          : const Duration(seconds: 4),
      action: r.coursesAdded > 0
          ? SnackBarAction(
              label: 'Undo',
              onPressed: () => _undoCsvImport(context, store, r.roundIds),
            )
          : null,
    ),
  );
}

/// Undoes a CSV import.
///
/// Deletes by the ids the import captured rather than by count, so a round the
/// user posted in the meantime is never the one that disappears.
void _undoCsvImport(BuildContext context, GolfStore store, List<String> ids) {
  final messenger = ScaffoldMessenger.of(context);
  final removed = store.removeRounds(ids);
  if (removed == 0) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Those rounds are already gone.')),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Removed $removed imported ${removed == 1 ? 'round' : 'rounds'}.',
      ),
    ),
  );
}

String _csvSummary(CsvPreview p) {
  final b = StringBuffer('Adds ${plural(p.roundsAdded, 'round')}');
  if (p.coursesAdded > 0) {
    b.write(
      ' and creates ${plural(p.coursesAdded, 'course')} the app does not '
      'have. A created course keeps the par total from the file spread evenly '
      'across its holes, so edit the pars before trusting its differentials.',
    );
  } else {
    b.write(', matched to courses you already have.');
  }
  if (p.roundsSkipped > 0) {
    b.write(
      ' ${plural(p.roundsSkipped, 'round')} already posted will be skipped.',
    );
  }
  return b.toString();
}

/// One line per kind of thing the restore will bring in, so the confirmation
/// says the same thing the backup actually carries.
String _restoreSummary(BackupPreview p) {
  final parts = <String>[
    if (p.roundsAdded > 0) plural(p.roundsAdded, 'round'),
    if (p.coursesAdded > 0) plural(p.coursesAdded, 'course'),
    if (p.colorsChanged > 0)
      '${p.colorsChanged} score ${p.colorsChanged == 1 ? 'color' : 'colors'}',
    if (p.photosRestored > 0) plural(p.photosRestored, 'photo'),
    if (p.themeChanged) 'appearance',
  ];
  if (p.themeChanged && parts.length == 1) {
    return 'Restores the appearance setting from the backup.';
  }
  return 'Adds ${parts.join(', ')}. '
      'Existing courses are left alone; backup settings are restored '
      'when they differ.';
}

/// Shown when the backup holds nothing this app is missing. Worth naming what
/// the file *did* contain, because the usual cause is importing a backup you
/// already restored rather than a wrong file.
String _nothingNewMessage(Backup b, BackupPreview p) {
  final held = <String>[
    if (b.rounds.isNotEmpty) plural(b.rounds.length, 'round'),
    if (b.courses.isNotEmpty) plural(b.courses.length, 'course'),
    if (b.scoreColors != null && b.scoreColors!.isNotEmpty) 'settings',
    if (b.photos.isNotEmpty) plural(b.photos.length, 'photo'),
    if (b.themeMode != null) 'appearance',
  ];
  if (held.isEmpty) return 'That backup is empty.';
  return 'Nothing new: this backup has ${held.join(', ')}, '
      'all of which are already here.';
}
