
import 'package:flutter/material.dart';

import 'course_catalog.dart';
import 'design_tokens.dart';
import 'models.dart';
import 'scan_service.dart';
import 'opengolf.dart';
import 'photo_source_sheet.dart';
import 'store.dart';
import 'scorecard_widgets.dart';
import 'add_course_screen.dart';

// ---------------- COURSES ----------------
class CoursesPage extends StatefulWidget {
  final GolfStore store;
  final CourseRatingCatalog? catalog;
  final OpenGolfApi? openGolfApi;
  const CoursesPage({
    super.key,
    required this.store,
    this.catalog,
    this.openGolfApi,
  });
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  /// Past this many saved courses the card list collapses into a dropdown.
  static const _savedCourseDropdownThreshold = 5;

  String q = '';
  String? selectedCourseId;
  String? selectedTeeId;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  CourseRatingCatalog? _courseCatalog;
  String? _courseCatalogError;
  late final OpenGolfApi _openGolfApi = widget.openGolfApi ?? OpenGolfApi();
  final Set<String> _loadingCatalogCourses = {};

  @override
  void initState() {
    super.initState();
    final catalog = widget.catalog;
    if (catalog == null) {
      _loadCourseCatalog();
    } else {
      _courseCatalog = catalog;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    if (widget.openGolfApi == null) _openGolfApi.close();
    super.dispose();
  }

  Future<void> _loadCourseCatalog() async {
    try {
      final catalog = await CourseRatingCatalog.load();
      if (mounted) setState(() => _courseCatalog = catalog);
    } catch (error) {
      if (mounted) setState(() => _courseCatalogError = '$error');
    }
  }

  void _onSearchChanged(String v) {
    setState(() => q = v);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final local = store.searchCourses(q);
    final catalogMatches = q.trim().length >= 2
        ? (_courseCatalog?.search(q) ?? const <CourseCatalogCourse>[])
        : const <CourseCatalogCourse>[];
    // Keep the selection stable while typing: only reset when the
    // selected course no longer exists (deleted).
    if (selectedCourseId == null ||
        store.courseById(selectedCourseId!) == null) {
      selectedCourseId = local.isNotEmpty ? local.first.id : null;
      selectedTeeId = null;
    }
    final course = selectedCourseId == null
        ? null
        : store.courseById(selectedCourseId!);
    if (course != null &&
        (selectedTeeId == null ||
            !course.tees.any((t) => t.id == selectedTeeId))) {
      selectedTeeId = course.defaultTee.id;
    }
    final tee = course == null
        ? null
        : (store.teeById(course.id, selectedTeeId ?? '') ?? course.defaultTee);
    String teeLabel(Tee t) =>
        '${t.name} • ${t.rating}/${t.slope} • Par ${t.par}';

    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      body: ListView(
        padding: const EdgeInsets.all(Insets.gutter),
        children: [
          TextField(
            key: const ValueKey('course-search'),
            controller: _searchController,
            focusNode: _searchFocus,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search Courses',
            ),
            onChanged: _onSearchChanged,
          ),
          if (q.trim().length >= 2) ...[
            const SizedBox(height: 4),
            Text(
              'LOCAL COURSE RATINGS',
              style: AppType.meta.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_courseCatalog == null && _courseCatalogError == null)
              const LinearProgressIndicator(),
            if (_courseCatalogError != null)
              Text(
                'Course catalog unavailable: $_courseCatalogError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_courseCatalog != null && catalogMatches.isEmpty)
              Text(
                'No course-rating matches.',
                style: AppType.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            if (catalogMatches.length == 15)
              Text(
                'Showing up to 15 matches. Add a city or course name to narrow results.',
                style: AppType.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            for (final c in catalogMatches)
              Card(
                margin: const EdgeInsets.only(top: Insets.sm),
                child: ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(c.name),
                  subtitle: Text(
                    [
                      c.city,
                      c.state,
                    ].where((part) => part.isNotEmpty).join(', '),
                  ),
                  trailing: TextButton(
                    onPressed: _loadingCatalogCourses.contains(c.catalogCourseId)
                        ? null
                        : () => _openCatalogCourse(c),
                    child: _loadingCatalogCourses.contains(c.catalogCourseId)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _catalogImported(c) ? 'Update course' : 'Import',
                          ),
                  ),
                  onTap: () => _openCatalogCourse(c),
                ),
              ),
            const SizedBox(height: 4),
            const Divider(),
          ],
          const SizedBox(height: 4),
          Text(
            'SAVED ON THIS DEVICE',
            style: AppType.meta.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (local.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No saved courses match.',
                style: AppType.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (local.isNotEmpty &&
              store.courses.length > _savedCourseDropdownThreshold)
            _savedCourseDropdown(context, local, course)
          else
            for (final c in local)
              Card(
                margin: const EdgeInsets.only(top: Insets.xs),
                color: c.id == selectedCourseId
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Insets.sm,
                  ),
                  selected: c.id == selectedCourseId,
                  selectedColor: Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer,
                  leading: Icon(
                    c.id == selectedCourseId
                        ? Icons.golf_course
                        : Icons.golf_course_outlined,
                    color: c.id == selectedCourseId
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(c.name, key: ValueKey('course-name-${c.id}')),
                  subtitle: Text(
                    [
                      // A scanned card does not always say where the course is, and
                      // a dangling ", " looks like a bug rather than a blank.
                      [c.city, c.state].where((p) => p.isNotEmpty).join(', '),
                      '${c.tees.length} tee${c.tees.length == 1 ? '' : 's'}',
                    ].where((p) => p.isNotEmpty).join(' • '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('edit-course-${c.id}'),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit course',
                        onPressed: () => _openEditCourse(c),
                      ),
                      IconButton(
                        key: ValueKey('delete-course-${c.id}'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove course',
                        onPressed: () => _confirmDelete(c),
                      ),
                    ],
                  ),
                  // Tapping the row selects it for the scorecard below; the
                  // pencil opens the editor.
                  onTap: () => setState(() {
                    selectedCourseId = c.id;
                    selectedTeeId = null;
                  }),
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openAddCourse(),
              icon: const Icon(Icons.add),
              label: const Text('Add manually'),
            ),
          ),
          const Divider(),
          if (course == null || tee == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No course selected. Search local ratings or add a course manually.',
              ),
            ),
          if (course != null && tee != null) ...[
            SizedBox(
              width: double.infinity,
              child: DropdownButtonFormField<String>(
                key: ValueKey('tee-dropdown-${course.id}'),
                initialValue: tee.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Teebox'),
                // The closed field shows plain text; the open menu boxes
                // each option so adjacent tees don't run together.
                selectedItemBuilder: (context) => [
                  for (final t in course.tees)
                    Text(teeLabel(t), overflow: TextOverflow.ellipsis),
                ],
                items: [
                  for (final t in course.tees)
                    DropdownMenuItem(
                      value: t.id,
                      child: Container(
                        key: ValueKey('tee-option-${t.id}'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.sm,
                          vertical: Insets.xs,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(Insets.sm),
                        ),
                        child: Text(
                          teeLabel(t),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => selectedTeeId = v),
              ),
            ),
            Container(
              key: const ValueKey('scorecard-outline'),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              clipBehavior: Clip.antiAlias,
              child: scorecardTable(course, tee),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => photoUsable(course.imagePath)
                    ? showCoursePhoto(
                        context,
                        course.name,
                        course.imagePath,
                        onDelete: () => _deleteCoursePhoto(course),
                      )
                    : _addCoursePhoto(course),
                icon: Icon(
                  photoUsable(course.imagePath)
                      ? Icons.photo_outlined
                      : Icons.add_a_photo_outlined,
                ),
                label: Text(
                  photoUsable(course.imagePath)
                      ? 'View Scorecard Photo'
                      : 'Save Blank Scorecard',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Compact course picker shown once the saved list outgrows cards.
  ///
  /// The dropdown holds the same search-filtered courses the cards would;
  /// edit and delete act on the selected course so no action is lost.
  Widget _savedCourseDropdown(
    BuildContext context,
    List<Course> courses,
    Course? selected,
  ) {
    // The selection survives typing, so it can lag the filtered list; a
    // value outside the items would throw, hence the membership check.
    final value = courses.any((c) => c.id == selectedCourseId)
        ? selectedCourseId
        : null;
    return Card(
      margin: const EdgeInsets.only(top: Insets.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
        child: Row(
          children: [
            Icon(
              Icons.golf_course_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: Insets.xs),
            Expanded(
              child: DropdownButton<String>(
                key: const ValueKey('course-dropdown'),
                value: value,
                hint: const Text('Select a course'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final c in courses)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  selectedCourseId = v;
                  selectedTeeId = null;
                }),
              ),
            ),
            if (selected != null) ...[
              IconButton(
                key: ValueKey('edit-course-${selected.id}'),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit course',
                onPressed: () => _openEditCourse(selected),
              ),
              IconButton(
                key: ValueKey('delete-course-${selected.id}'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove course',
                onPressed: () => _confirmDelete(selected),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// True when the catalog entry is already saved — by id, or by unique
  /// name for pre-removal imports whose synthetic id no longer matches.
  bool _catalogImported(CourseCatalogCourse c) =>
      widget.store.courseById(c.catalogCourseId) != null ||
      widget.store.uniqueCourseByName(c.state, c.name, c.city) != null;

  Future<void> _openCatalogCourse(CourseCatalogCourse course) async {
    final catalog = _courseCatalog;
    if (catalog == null ||
        _loadingCatalogCourses.contains(course.catalogCourseId)) {
      return;
    }
    setState(() => _loadingCatalogCourses.add(course.catalogCourseId));
    late final List<CourseCatalogTee> catalogTees;
    try {
      catalogTees = await catalog.teesFor(course);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingCatalogCourses.remove(course.catalogCourseId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load local tee data: $error')),
      );
      return;
    }
    if (!mounted) return;
    if (catalogTees.isEmpty) {
      setState(() => _loadingCatalogCourses.remove(course.catalogCourseId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No usable tees were found locally.')),
      );
      return;
    }

    List<OpenGolfTee> onlineTees = const [];
    List<OpenGolfHoleFull> onlineHoles = const [];
    var onlineStatus =
        'Online scorecard data is unavailable. Tee ratings are '
        'filled from the local catalog; enter pars and yardages from the '
        'course scorecard before saving.';
    var onlineAttribution = false;
    try {
      final candidates = await _openGolfApi.search(
        '${course.name} ${course.city} ${course.state}',
      );
      final match = matchOnlineCatalogCourse(course, candidates);
      if (match == null) {
        onlineStatus =
            'No unambiguous online scorecard match was found. Local tee '
            'ratings are prefilled; verify pars and enter yardages manually.';
      } else {
        final data = await _openGolfApi.fetchScorecard(match.id);
        onlineTees = data.tees;
        onlineHoles = data.holes;
        onlineAttribution = true;
      }
    } on OpenGolfException catch (error) {
      onlineStatus = error.message;
    } catch (error) {
      onlineStatus = 'Online scorecard data could not be read: $error';
    }
    final imported = buildCourseCatalogTeeImport(
      courseId: course.catalogCourseId,
      catalogTees: catalogTees,
      onlineTees: onlineTees,
      onlineHoles: onlineHoles,
    );
    if (onlineAttribution) onlineStatus = imported.onlineStatus;
    if (!mounted) return;
    setState(() => _loadingCatalogCourses.remove(course.catalogCourseId));
    _searchFocus.unfocus();
    final existing =
        widget.store.courseById(course.catalogCourseId) ??
        widget.store.uniqueCourseByName(
          course.state,
          course.name,
          course.city,
        );
    if (existing != null) {
      await _openEditCourse(
        existing,
        importedCatalogTees: imported.tees,
        catalogParTotals: imported.expectedParByTee,
        missingParHolesByTee: imported.missingParHolesByTee,
        catalogOnlineStatus: onlineStatus,
        onlineAttribution: onlineAttribution,
      );
      return;
    }
    await _openAddCourse(
      catalogCourse: course,
      importedCatalogTees: imported.tees,
      catalogParTotals: imported.expectedParByTee,
      missingParHolesByTee: imported.missingParHolesByTee,
      catalogOnlineStatus: onlineStatus,
      onlineAttribution: onlineAttribution,
    );
  }

  Future<void> _openEditCourse(
    Course c, {
    CourseCatalogTee? catalogTee,
    List<Tee> importedCatalogTees = const [],
    Map<String, int> catalogParTotals = const {},
    Map<String, List<int>> missingParHolesByTee = const {},
    String? catalogOnlineStatus,
    bool onlineAttribution = false,
  }) async {
    final updated = await Navigator.of(context).push<Course>(
      MaterialPageRoute(
        builder: (_) => AddCourseScreen(
          existing: c,
          catalogTee: catalogTee,
          importedCatalogTees: importedCatalogTees,
          catalogParTotals: catalogParTotals,
          missingParHolesByTee: missingParHolesByTee,
          catalogOnlineStatus: catalogOnlineStatus,
          onlineAttribution: onlineAttribution,
        ),
      ),
    );
    if (updated != null) {
      widget.store.updateCourse(updated);
      setState(() {
        selectedCourseId = updated.id;
        selectedTeeId = updated.defaultTee.id;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${updated.name} updated.')));
      }
    }
  }

  Future<void> _openAddCourse({
    CourseCatalogCourse? catalogCourse,
    CourseCatalogTee? catalogTee,
    List<Tee> importedCatalogTees = const [],
    Map<String, int> catalogParTotals = const {},
    Map<String, List<int>> missingParHolesByTee = const {},
    String? catalogOnlineStatus,
    bool onlineAttribution = false,
  }) async {
    final created = await Navigator.of(context).push<Course>(
      MaterialPageRoute(
        builder: (_) => AddCourseScreen(
          catalogCourse: catalogCourse,
          catalogTee: catalogTee,
          importedCatalogTees: importedCatalogTees,
          catalogParTotals: catalogParTotals,
          missingParHolesByTee: missingParHolesByTee,
          catalogOnlineStatus: catalogOnlineStatus,
          onlineAttribution: onlineAttribution,
        ),
      ),
    );
    if (created != null) {
      widget.store.addCourse(created);
      _searchFocus.unfocus();
      _searchController.clear();
      setState(() {
        q = '';
        selectedCourseId = created.id;
        selectedTeeId = created.defaultTee.id;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${created.name} added — it now appears in search and scoring.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _addCoursePhoto(Course course) async {
    final result = await pickScorecardPhoto(context);
    if (result is! PhotoPicked) return;
    final path = await persistScanPhoto(result.file, course.id);
    if (!mounted) return;
    widget.store.updateCourse(course.copyWithImagePath(path));
    setState(() {});
  }

  Future<void> _deleteCoursePhoto(Course course) async {
    final old = course.imagePath;
    widget.store.updateCourse(course.copyWithImagePath(''));
    await deleteScanPhoto(old);
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete(Course c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
          'Rounds already posted here are kept, but the course disappears from search and scoring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.store.deleteCourse(c.id);
      await deleteScanPhoto(c.imagePath);
      setState(() {
        if (selectedCourseId == c.id) selectedCourseId = null;
      });
    }
  }
}
