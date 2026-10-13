import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('quick post selects a playable count for a nine-hole tee', (
    tester,
  ) async {
    final store = GolfStore();
    final seed = store.courses.first;
    store.addCourse(
      Course(
        id: 'short-tee-course',
        name: 'Nine Hole Place',
        city: seed.city,
        state: seed.state,
        custom: true,
        tees: [
          Tee(
            id: 'short-tee',
            name: 'Nine Hole Tee',
            rating: seed.tees.first.rating,
            slope: seed.tees.first.slope,
            holes: seed.tees.first.holes.take(9).toList(),
          ),
        ],
      ),
    );
    await pumpTallHome(tester, store);

    // Selecting a 9-hole course adapts the hole-count field to its tee.
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nine Hole Place').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Nine Hole Tee •'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('home-hole-count-selector')),
          )
          .initialValue,
      9,
    );
    await tester.tap(find.byKey(const ValueKey('home-hole-count-selector')));
    await tester.pumpAndSettle();
    expect(find.text('9 Holes'), findsWidgets);
    expect(find.text('18 Holes'), findsNothing);
    await tester.tap(find.text('9 Holes').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '45');
    await tester.pumpAndSettle();

    final ninePar = seed.tees.first.holes.take(9).fold(0, (s, h) => s + h.par);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Total score'))
          .decoration!
          .hintText,
      '$ninePar',
    );
    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Post Round'),
    );
    expect(btn.onPressed, isNotNull);
    expect(store.rounds, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();
    expect(store.rounds.single.holes, hasLength(9));
  });


  testWidgets('quick post on Home adds a typed 18-hole round to the store', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    expect(find.text('Quick score'), findsOneWidget);
    expect(find.text('18 Holes'), findsOneWidget);
    // The nine selector is hidden until 9 holes is picked.
    expect(find.text('Front 9'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '75');
    await tester.pumpAndSettle();
    // No summary line, no suffix echo, no helper, no Clear button.
    expect(find.textContaining('Total 75'), findsNothing);
    expect(find.text('Clear'), findsNothing);
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Total score'),
    );
    expect(field.decoration!.suffixText, isNull);
    expect(field.decoration!.helperText, isNull);

    expect(store.rounds, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();

    expect(store.rounds, hasLength(1));
    final r = store.rounds.single;
    expect(r.holes, hasLength(18));
    expect(r.totalGross, 75);
    expect(r.startHole, 0);
    expect(r.handicapIndexAtPlay, isNull);
    expect(r.courseHandicap, isNull);
    expect(r.differential(store.teeById(r.courseId, r.teeId)!), isNotNull);
    expect(r.format, 'stroke');
    // The round is linked to the tee shown in the dropdown.
    expect(store.teeById(r.courseId, r.teeId), isNotNull);
    // The box clears so the next round is not typed over the last one.
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Total score'))
          .controller!
          .text,
      isEmpty,
    );
  });


  testWidgets('quick post offers Save Scorecard next to the total', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    // The button sits beside the Total score field, and both halves are
    // the same width.
    final photo = find.byKey(const ValueKey('quick-score-photo'));
    expect(photo, findsOneWidget);
    expect(find.text('Save Scorecard'), findsOneWidget);
    final field = find.widgetWithText(TextField, 'Total score');
    expect(
      (tester.getCenter(photo).dy - tester.getCenter(field).dy).abs(),
      lessThan(40),
    );
    expect(
      (tester.getSize(photo).width - tester.getSize(field).width).abs(),
      lessThan(16),
    );

    // The actual pick needs a camera or gallery, which tests do not have;
    // the sheet opening with both sources is what is asserted here.
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
  });


  testWidgets('quick score shows the latest score for the selected course', (
    tester,
  ) async {
    final store = GolfStore();
    final crystalLake = store.courseById('crystal-lake')!;
    final white = crystalLake.tees.firstWhere((tee) => tee.name == 'White');
    final otherTee = Tee(
      id: 'other-course-white',
      name: white.name,
      rating: white.rating,
      slope: white.slope,
      holes: white.holes,
    );
    final otherCourse = Course(
      id: 'other-course',
      name: 'Other Course',
      city: '',
      state: '',
      custom: true,
      tees: [otherTee],
    );
    store.courses = [...store.courses, otherCourse];
    store.rounds = [
      Round(
        id: 'crystal-old',
        courseId: crystalLake.id,
        teeId: white.id,
        playedAt: DateTime(2026, 1, 1),
        holes: [for (var i = 0; i < 9; i++) HoleScore(score: 5)],
      ),
      Round(
        id: 'crystal-last',
        courseId: crystalLake.id,
        teeId: white.id,
        playedAt: DateTime(2026, 1, 2),
        holes: [for (var i = 0; i < 9; i++) HoleScore(score: 4)],
      ),
      Round(
        id: 'other-last',
        courseId: otherCourse.id,
        teeId: otherTee.id,
        playedAt: DateTime(2026, 1, 3),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5)],
      ),
    ];
    await pumpTallHome(tester, store);

    expect(
      find.text('Last score at this course: 90 • 18 holes • White'),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crystal Lake Golf Club').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Last score at this course: 36 • 9 holes • White'),
      findsOneWidget,
    );
  });


  testWidgets('Home hole count selector only offers 9 and 18 holes', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    await chooseHoleCount(
      tester,
      selectorKey: 'home-hole-count-selector',
      count: 9,
    );
    expect(find.textContaining('White • Front 9 33.8/125'), findsOneWidget);
    expect(find.textContaining('Back 9 34.5/123'), findsNothing);
    await tester.tap(find.text('Back 9'));
    await tester.pumpAndSettle();
    expect(find.textContaining('White • Back 9 34.5/123'), findsOneWidget);
    expect(find.textContaining('Front 9 33.8/125'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-hole-count-selector')));
    await tester.pumpAndSettle();
    expect(find.text('9 Holes'), findsWidgets);
    expect(find.text('18 Holes'), findsWidgets);
    expect(find.text('10 Holes'), findsNothing);
    expect(find.text('17 Holes'), findsNothing);
  });


  testWidgets('quick post caps holes at par plus five while establishing', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);
    await chooseHoleCount(
      tester,
      selectorKey: 'home-hole-count-selector',
      count: 9,
    );

    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '90');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();

    final r = store.rounds.single;
    final tee = store.teeById(r.courseId, r.teeId)!;
    for (var i = 0; i < r.holes.length; i++) {
      expect(
        r.holes[i].score,
        lessThanOrEqualTo(tee.holes[r.startHole + i].par + 5),
      );
    }
    expect(r.totalGross, lessThan(90));
    expect(find.textContaining('capped at max'), findsOneWidget);
  });


  testWidgets('picking 9 holes reveals front/back, and back 9 changes par', (
    tester,
  ) async {
    final store = GolfStore();
    final baseCourse = store.courses.first;
    final baseTee = baseCourse.defaultTee;
    final tee = Tee(
      id: 'split-rated-tee',
      name: 'White',
      rating: baseTee.rating,
      slope: baseTee.slope,
      frontNineRating: 33.8,
      frontNineSlope: 119,
      backNineRating: 34.5,
      backNineSlope: 124,
      holes: baseTee.holes,
    );
    store.courses = [
      Course(
        id: baseCourse.id,
        name: baseCourse.name,
        city: baseCourse.city,
        state: baseCourse.state,
        tees: [tee],
      ),
    ];
    await pumpTallHome(tester, store);

    await chooseHoleCount(
      tester,
      selectorKey: 'home-hole-count-selector',
      count: 9,
    );
    expect(find.text('Front 9'), findsOneWidget);
    expect(find.text('Back 9'), findsOneWidget);
    expect(find.textContaining('White • Front 9 33.8/119'), findsOneWidget);
    expect(find.textContaining('Back 9 34.5/124'), findsNothing);

    final field = find.widgetWithText(TextField, 'Total score');
    await tester.enterText(field, '36');
    await tester.pumpAndSettle();

    // The Total field's placeholder is the only place the chosen nine shows
    // up in the par. Front 9 is par 35 and back 9 is par 36 on the seed tee,
    // so a widget that ignored the front/back pick would report the same par
    // either way.
    String parHint() => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Total score'))
        .decoration!
        .hintText!;

    expect(tee.parTotalFrom(0, 9), isNot(tee.parTotalFrom(9, 9)));
    expect(parHint(), '${tee.parTotalFrom(0, 9)}');

    await tester.tap(find.text('Back 9'));
    await tester.pumpAndSettle();
    expect(find.textContaining('White • Back 9 34.5/124'), findsOneWidget);
    expect(find.textContaining('Front 9 33.8/119'), findsNothing);
    // Switching nine clears the box, because the scores typed so far were
    // entered against the other nine's pars. Retype them to read the new par.
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, '36');
    await tester.pumpAndSettle();
    expect(parHint(), '${tee.parTotalFrom(9, 9)}');

    await tester.tap(find.widgetWithText(FilledButton, 'Post Round'));
    await tester.pumpAndSettle();

    final r = store.rounds.single;
    expect(r.holes, hasLength(9));
    expect(r.startHole, 9);
    expect(r.isBackNine, isTrue);
  });

  testWidgets('quick post refuses an impossible total and saves nothing', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    // 10 strokes over 18 holes cannot be laid out as legal hole scores.
    await tester.enterText(find.widgetWithText(TextField, 'Total score'), '10');
    await tester.pumpAndSettle();

    // The button is disabled rather than saving a round nobody played.
    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Post Round'),
    );
    expect(btn.onPressed, isNull);
    expect(
      find.text('A total of 10 is not a score for 18 holes'),
      findsOneWidget,
    );
    expect(store.rounds, isEmpty);
  });


  testWidgets('quick post rejects a total that is not a number', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    await tester.enterText(
      find.widgetWithText(TextField, 'Total score'),
      '75.5',
    );
    await tester.pumpAndSettle();

    expect(find.text('"75.5" is not a number'), findsOneWidget);
    expect(store.rounds, isEmpty);
  });


  testWidgets('quick post is offered on the Play page too, with front/back', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    // The Play page is the detailed path, but it must offer the same nine
    // choice, or a back nine could be recorded from Home but not here.
    expect(find.text('Front 9'), findsNothing);
    await chooseHoleCount(
      tester,
      selectorKey: 'play-hole-count-selector',
      count: 9,
    );
    expect(find.text('Front 9'), findsOneWidget);
    expect(find.text('Back 9'), findsOneWidget);

    // Par for hole 1 is read from the chosen nine: the editor's header is
    // "Hole 1 • Par N". Hole 1 of the back nine is the tee's hole 10, so the
    // header must follow the pick.
    final tee = store.courses.first.tees.first;
    expect(tee.holes[0].par, isNot(tee.holes[9].par));
    expect(find.text('Hole 1 • Par ${tee.holes[0].par}'), findsOneWidget);

    await tester.tap(find.text('Back 9'));
    await tester.pumpAndSettle();
    expect(find.text('Hole 1 • Par ${tee.holes[9].par}'), findsOneWidget);
    expect(find.text('Hole 1 • Par ${tee.holes[0].par}'), findsNothing);
  });

}
