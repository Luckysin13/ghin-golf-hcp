import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/add_course_screen.dart';
import 'package:ghin_golf/courses_page.dart';
import 'package:ghin_golf/scorecard_widgets.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';

void main() {
  testWidgets('tapping a saved course row selects it, not its editor', (
    tester,
  ) async {
    final store = GolfStore();
    final seed = store.courses.first;
    store.addCourse(
      Course(
        id: 'custom-name-tap',
        name: 'North Course',
        city: 'Austin',
        state: 'TX',
        custom: true,
        tees: [
          Tee(
            id: 'custom-name-tap-white',
            name: 'White',
            rating: seed.defaultTee.rating,
            slope: seed.defaultTee.slope,
            holes: seed.defaultTee.holes,
          ),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: CoursesPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Search Courses'), findsOneWidget);
    expect(find.textContaining('yours'), findsNothing);

    // Tapping the row selects it for the scorecard below; the editor opens
    // only from the pencil button.
    await tester.tap(find.text('Austin, TX • 1 tee'));
    await tester.pumpAndSettle();
    expect(find.text('Edit course'), findsNothing);

    final scheme = Theme.of(
      tester.element(find.byType(CoursesPage)),
    ).colorScheme;
    Card rowCard(String courseId) => tester.widget<Card>(
      find.ancestor(
        of: find.byKey(ValueKey('course-name-$courseId')),
        matching: find.byType(Card),
      ),
    );
    expect(rowCard('custom-name-tap').color, scheme.primaryContainer);
    expect(rowCard('crystal-lake').color, isNull);
  });


  testWidgets('seeded Crystal Lake course opens in the editor', (tester) async {
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: CoursesPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit-course-crystal-lake')));
    await tester.pumpAndSettle();
    expect(find.text('Edit course'), findsOneWidget);
    expect(find.text('Crystal Lake Golf Club'), findsWidgets);
  });


  testWidgets('saving a seeded course keeps it seeded', (tester) async {
    final seed = GolfStore().courseById('crystal-lake')!;
    Course? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context)
                    .push<Course>(
                      MaterialPageRoute(
                        builder: (_) => AddCourseScreen(existing: seed),
                      ),
                    )
                    .then((course) => result = course);
              },
              child: const Text('Edit seeded course'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit seeded course'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('HOLE 1'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    Finder hcpField(int holeIndex) => find.byWidgetPredicate(
      (widget) =>
          widget is TextFormField &&
          widget.key is ValueKey &&
          (widget.key! as ValueKey).value.toString().endsWith('-$holeIndex'),
    );
    await tester.enterText(hcpField(0), '18');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('HOLE 5'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(hcpField(4), '');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.custom, isFalse);
    expect(result!.tees.first.holes[0].strokeIndex, 18);
    expect(result!.tees.first.holes[4].strokeIndex, isNull);
  });


  testWidgets('adding a course clears and unfocuses the search field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(MaterialApp(home: CoursesPage(store: store)));
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey('course-search'));
    await tester.enterText(search, 'x');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add manually'));
    await tester.pumpAndSettle();

    Future<void> enterField(String label, String value) async {
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.enterText(field, value);
    }

    await enterField('Course name *', 'New Course');
    await enterField('Rating *', '70.0');
    await enterField('Slope *', '120');
    await enterField('Front 9 rating', '34.5');
    await enterField('Front 9 slope', '118');
    await enterField('Back 9 rating', '35.5');
    await enterField('Back 9 slope', '122');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
    await tester.pumpAndSettle();
    final save = find.text('Save course');
    expect(save, findsOneWidget);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final created = store.courses.singleWhere(
      (course) => course.name == 'New Course',
    );
    expect(created.tees.single.frontNineRating, 34.5);
    expect(created.tees.single.frontNineSlope, 118);
    expect(created.tees.single.backNineRating, 35.5);
    expect(created.tees.single.backNineSlope, 122);
    final searchField = tester.widget<TextField>(search);
    expect(searchField.controller?.text, isEmpty);
    expect(searchField.focusNode?.hasFocus, isFalse);
  });


  testWidgets('OCR inspector shows the raw read text', (tester) async {
    const stub = 'BLUE 402 515 178\nPAR 4 5 3';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OcrTextDialog(text: stub)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What the scan read'), findsOneWidget);
    expect(find.text(stub), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('What the scan read'), findsNothing);
  });


  testWidgets('scorecard cells are centered with hole separators', (
    tester,
  ) async {
    final course = GolfStore().courses.first;
    final originalTee = course.tees.first;
    final tee = Tee(
      id: originalTee.id,
      name: originalTee.name,
      rating: originalTee.rating,
      slope: originalTee.slope,
      frontNineRating: originalTee.frontNineRating,
      frontNineSlope: originalTee.frontNineSlope,
      backNineRating: originalTee.backNineRating,
      backNineSlope: originalTee.backNineSlope,
      holes: [
        for (var i = 0; i < originalTee.holes.length; i++)
          HoleInfo(
            number: i + 1,
            par: originalTee.holes[i].par,
            yardage: originalTee.holes[i].yardage,
            strokeIndex: i == 0 ? null : originalTee.holes[i].strokeIndex,
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: scorecardTable(course, tee))),
    );
    await tester.pumpAndSettle();
    expect(find.text('FRONT 9'), findsOneWidget);
    expect(find.text('BACK 9'), findsOneWidget);
    expect(find.text('HCP'), findsNWidgets(2));
    expect(find.text('-'), findsOneWidget);
    expect(find.textContaining('Rating 70.4 • Slope 139'), findsOneWidget);
    // Every hole number cell is centered.
    final one = tester.widget<Text>(find.text('1').first);
    expect(one.textAlign, TextAlign.center);
    // Separators: non-last cells carry a right border.
    final seps = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          (w.decoration as BoxDecoration?)?.border is Border &&
          ((w.decoration as BoxDecoration).border as Border).right !=
              BorderSide.none,
    );
    expect(seps, findsWidgets);
  });


  testWidgets('add-course form has no SI controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AddCourseScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Add local course'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'\bSI\b')), findsNothing);
    expect(find.text('Par: 4'), findsWidgets);
    expect(find.text('Yds'), findsNothing);
  });


  testWidgets('course form Holes and Yardages chips show no checkmark', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AddCourseScreen()));
    await tester.pumpAndSettle();

    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList();
    expect(chips, isNotEmpty);
    for (final chip in chips) {
      expect(chip.showCheckmark, isFalse);
    }
  });


  testWidgets('saved scorecard photo stays pinned while course form scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final photo = File(
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    ).absolute;
    expect(photo.existsSync(), isTrue);
    final course = Course(
      id: 'photo-course',
      name: 'Crystal Lake Golf Club',
      city: '',
      state: '',
      imagePath: photo.path,
      tees: [
        Tee(
          id: 'white',
          name: 'White',
          rating: 71.2,
          slope: 124,
          holes: [
            for (var i = 0; i < 18; i++)
              HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
          ],
        ),
      ],
      custom: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: AddCourseScreen(existing: course)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'initial pinned layout');

    final pinnedPhoto = find.byKey(const ValueKey('pinned-scorecard-photo'));
    expect(find.text('Saved scorecard photo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('course-scorecard-interactive-viewer')),
      findsOneWidget,
    );
    final image = find.byType(Image).first;
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
    expect(tester.getSize(image).width, greaterThan(200));
    expect(tester.getSize(image).height, greaterThan(140));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.text('150%'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset zoom and pan'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    final initialTop = tester.getTopLeft(pinnedPhoto).dy;
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(pinnedPhoto, findsOneWidget);
    expect(tester.getTopLeft(pinnedPhoto).dy, initialTop);
    expect(tester.takeException(), isNull);
  });


}
