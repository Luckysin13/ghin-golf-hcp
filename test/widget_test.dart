import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/app_theme.dart';
import 'package:ghin_golf/design_tokens.dart';
import 'package:ghin_golf/ghin_brand_mark.dart';
import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/post_page.dart';
import 'package:ghin_golf/score_widgets.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';
import 'test_helpers.dart';

void main() {
  testWidgets('GHIN app boots to Home with handicap card', (tester) async {
    final store = GolfStore();
    await tester.pumpWidget(GhinApp(store: store));
    expect(find.text('HANDICAP INDEX'), findsOneWidget);
    expect(find.byType(GhinBrandMark), findsOneWidget);
    expect(find.text('GHIN HCP'), findsOneWidget);
    expect(find.text('YOUR GAME, AT A GLANCE'), findsNothing);
    expect(find.text('Handicap and recent play'), findsNothing);
    expect(find.text('No previous score at this course'), findsOneWidget);
    // Quick posting is the only route from Home now: the shortcut buttons to
    // the Play and Courses tabs are gone, so the card must be present here.
    expect(find.text('Quick score'), findsOneWidget);
    expect(find.text('Post Score'), findsNothing);
    expect(find.text('Find Course'), findsNothing);
    // The per-hole par row is gone too, so no "P1 4" style labels on Home.
    expect(find.textContaining(RegExp(r'^P\d+ ')), findsNothing);
  });


  testWidgets('Quick post opens on the White tee, not the longest one', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    // The seed tee list runs longest first, so a tees.first default would show
    // Black here. White is the tee most golfers actually play.
    expect(store.courses.first.tees.first.name, 'Black');
    expect(store.courses.first.defaultTee.name, 'White');
    expect(find.textContaining('White •'), findsOneWidget);
    expect(find.textContaining('Black •'), findsNothing);
    expect(find.text('Enter your total'), findsNothing);
    final teeSelector = find.byType(DropdownButtonFormField<String>).at(1);
    final holeSelector = find.byKey(const ValueKey('home-hole-count-selector'));
    expect(
      tester.getTopLeft(holeSelector).dy -
          tester.getBottomRight(teeSelector).dy,
      greaterThanOrEqualTo(8),
    );
  });


  testWidgets('Home and Play show tees as name • rating/slope • Par ##', (
    tester,
  ) async {
    final store = GolfStore();
    await pumpTallHome(tester, store);

    final tee = store.courses.first.defaultTee;
    String label(Tee t) =>
        '${t.name} • ${t.rating.toStringAsFixed(1)}/${t.slope} • Par ${t.par}';

    // Home QuickPost tee selector carries the same format as the Courses page.
    expect(find.text(label(tee)), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    // The Play tee selector shows the identical label before opening...
    expect(find.text(label(tee)), findsOneWidget);

    // ...and every option in the dropdown does too.
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    for (final t in store.courses.first.tees) {
      expect(find.text(label(t)), findsWidgets, reason: label(t));
    }
  });


  testWidgets('Home and Play course dropdowns are alphabetically sorted', (
    tester,
  ) async {
    final store = GolfStore();
    final tee = store.courses.first.defaultTee;
    store.courses = [
      for (final name in ['Zeta Course', 'Alpha Course', 'Middle Course'])
        Course(
          id: name.toLowerCase().replaceAll(' ', '-'),
          name: name,
          city: '',
          state: '',
          tees: [tee],
        ),
    ];
    const expected = ['Alpha Course', 'Middle Course', 'Zeta Course'];

    Future<void> expectSortedCourseMenu() async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      final yPositions = [
        for (final name in expected) tester.getCenter(find.text(name).last).dy,
      ];
      expect(yPositions, orderedEquals(yPositions.toList()..sort()));
      await tester.tap(find.text('Alpha Course').last);
      await tester.pumpAndSettle();
    }

    await pumpTallHome(tester, store);
    await expectSortedCourseMenu();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await expectSortedCourseMenu();
  });


  testWidgets('Play course and tee card matches Home quick score padding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GhinApp(store: GolfStore()));
    await tester.pumpAndSettle();

    final homeList = tester.widget<ListView>(find.byType(ListView).first);
    final homeQuickCard = find.ancestor(
      of: find.text('Quick score'),
      matching: find.byType(Card),
    );
    final homeCardPadding = tester.widget<Padding>(
      find
          .descendant(
            of: homeQuickCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding == const EdgeInsets.all(12),
            ),
          )
          .first,
    );
    expect(homeList.padding, const EdgeInsets.all(Insets.gutter));
    expect(homeCardPadding.padding, const EdgeInsets.all(12));

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    final playList = tester.widget<ListView>(find.byType(ListView).first);
    final playCardPadding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(Card).first,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding == const EdgeInsets.all(12),
            ),
          )
          .first,
    );
    expect(playList.padding, homeList.padding);
    expect(playCardPadding.padding, homeCardPadding.padding);
    final teeSelector = find.byType(DropdownButtonFormField<String>).at(1);
    final holeSelector = find.byKey(const ValueKey('play-hole-count-selector'));
    expect(
      tester.widget<DropdownButtonFormField<int>>(holeSelector).initialValue,
      18,
    );
    expect(
      tester.getTopLeft(holeSelector).dy -
          tester.getBottomRight(teeSelector).dy,
      greaterThanOrEqualTo(8),
    );
    expect(
      tester.getCenter(holeSelector).dx,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
        1,
      ),
    );
  });


  testWidgets('Play score entry uses the hole score-vs-par color scheme', (
    tester,
  ) async {
    final store = GolfStore();
    await tester.pumpWidget(GhinApp(store: store));
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Hole 1 • Par 4'), findsOneWidget);
    final holeTitle = tester.widget<Text>(find.text('Hole 1 • Par 4'));
    final titleSpans = (holeTitle.textSpan as TextSpan).children!;
    expect(titleSpans[0].style?.fontSize, 22);
    expect(titleSpans[1].style?.fontSize, 14);
    final selectedHole = tester.widget<Container>(
      find.byKey(const ValueKey('play-hole-chip-0')),
    );
    final selectedHoleDecoration = selectedHole.decoration as BoxDecoration;
    expect(
      (selectedHoleDecoration.border as Border).top.color,
      AppTheme.light.colorScheme.primary,
    );
    expect((selectedHoleDecoration.border as Border).top.width, 3);
    expect(find.text('Hole 1 of 18'), findsNothing);
    expect(find.text('< Prev'), findsOneWidget);
    expect(find.text('Next >'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('play-prev-hole')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('play-next-hole')))
          .onPressed,
      isNotNull,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.style?.fontSize == 26,
      ),
      findsNothing,
    );
    // The top three pills share one row at the same width.
    final tops = [
      for (final label in ['Eagle', 'Birdie', 'Par'])
        tester.getCenter(find.widgetWithText(ScorePill, label)),
    ];
    expect((tops[1].dy - tops[0].dy).abs(), lessThan(1));
    expect((tops[2].dy - tops[0].dy).abs(), lessThan(1));
    final topWidths = [
      for (final label in ['Eagle', 'Birdie', 'Par'])
        tester.getSize(find.widgetWithText(ScorePill, label)).width,
    ];
    expect(topWidths[1], topWidths[0]);
    expect(topWidths[2], topWidths[0]);
    for (final label in ['GIR', 'Putts', 'Penalty', 'Fairway']) {
      final controls = find.byKey(
        ValueKey('play-controls-${label.toLowerCase()}'),
      );
      expect(controls, findsOneWidget);
      expect(
        tester.getTopLeft(controls).dx - tester.getTopLeft(find.text(label)).dx,
        greaterThanOrEqualTo(80),
      );
    }
    final holeStrip = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    final currentHoleCard = find.ancestor(
      of: find.text('Hole 1 • Par 4'),
      matching: find.byType(Card),
    );
    expect(
      tester.getTopLeft(currentHoleCard.first).dy -
          tester.getBottomLeft(holeStrip).dy,
      Insets.md,
    );
    final birdieFinder = find.widgetWithText(ScorePill, 'Birdie');
    final birdie = tester.widget<ScorePill>(birdieFinder);
    final birdieColor = Color(store.scoreColorValue(-1));
    expect(birdie.color, birdieColor);
    expect(birdie.selected, isFalse);
    final birdieMat = tester.widget<Material>(
      find.descendant(of: birdieFinder, matching: find.byType(Material)),
    );
    expect(birdieMat.color, birdieColor.withValues(alpha: 0.35));
    expect(
      (birdieMat.shape as StadiumBorder).side.color,
      birdieColor.withValues(alpha: 0.9),
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: birdieFinder, matching: find.text('Birdie')),
          )
          .style
          ?.color,
      AppTheme.light.colorScheme.onSurface,
    );
    expect(
      tester.widget<ScorePill>(find.widgetWithText(ScorePill, 'Par')).selected,
      isTrue,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('play-hole-chip-0'))).width,
      54,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('play-hole-chip-0')),
              matching: find.text('1'),
            ),
          )
          .style
          ?.fontSize,
      22,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('play-hole-score-0')))
          .color,
      const Color(0xFF607D8B),
    );
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('play-hole-number-0')))
          .color,
      AppTheme.light.colorScheme.primaryContainer,
    );

    // Birdie the hole (auto-advances), then return to confirm the chip and
    // hole strip still show the recorded score.
    await tester.tap(
      find.byWidgetPredicate((w) => w is ScorePill && w.label == 'Birdie'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hole 2 • Par 4'), findsOneWidget);
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('play-hole-score-0')))
          .color,
      const Color(0xFF43A047),
    );
    // Back to hole 1 via its strip chip.
    await tester.tap(find.byKey(const ValueKey('play-hole-chip-0')));
    await tester.pumpAndSettle();
    expect(find.text('Hole 1 • Par 4'), findsOneWidget);

    final birdieChip = tester.widget<ScorePill>(
      find.byWidgetPredicate((w) => w is ScorePill && w.label == 'Birdie'),
    );
    expect(birdieChip.selected, isTrue);
    expect(birdieChip.color, const Color(0xFF43A047));
  });


  testWidgets('Play hole navigation follows the score and stops at both ends', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = GolfStore();
    await tester.pumpWidget(GhinApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    final previous = find.byKey(const ValueKey('play-prev-hole'));
    final next = find.byKey(const ValueKey('play-next-hole'));
    final tee = store.courses.first.defaultTee;

    for (var hole = 2; hole <= 18; hole++) {
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        find.text('Hole $hole • Par ${tee.holes[hole - 1].par}'),
        findsOneWidget,
      );
    }
    expect(tester.widget<TextButton>(next).onPressed, isNull);
    expect(tester.widget<TextButton>(previous).onPressed, isNotNull);

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Hole 17 • Par ${tee.holes[16].par}'), findsOneWidget);
  });


  testWidgets('light theme keeps play hole and shot labels readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PostPage(store: GolfStore()),
      ),
    );
    await tester.pumpAndSettle();

    final scheme = AppTheme.light.colorScheme;
    expect(
      tester.widget<Text>(find.text('Hole 1 • Par 4')).style?.color,
      scheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('GIR')).style?.color,
      scheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('Fairway')).style?.color,
      scheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('Yes')).style?.color,
      scheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('No')).style?.color,
      scheme.onSecondaryContainer,
    );

    for (final direction in ['L', 'H', 'R']) {
      expect(
        tester.widget<Text>(find.text(direction)).style?.color,
        scheme.onSurface,
      );
    }
  });


  testWidgets('light theme shows the Home hole-count dropdown choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(store: GolfStore()),
      ),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('home-hole-count-selector'));
    expect(
      tester.widget<DropdownButtonFormField<int>>(selector).initialValue,
      18,
    );
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.text('9 Holes'), findsWidgets);
    expect(find.text('18 Holes'), findsWidgets);
  });


  testWidgets('score colors are user-editable and stick in the store', (
    tester,
  ) async {
    final store = GolfStore();
    await tester.pumpWidget(GhinApp(store: store));
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Score colors'), findsOneWidget);
    expect(find.text('Triple or worse'), findsOneWidget);

    // Open the Birdie row and pick the dark-green swatch (34px circle;
    // the 22px row dot shares the default color, so match by size).
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is ListTile && (w.title as Text?)?.data == 'Birdie',
      ),
    );
    await tester.pumpAndSettle();
    const pick = Color(0xFF1B5E20);
    final dots = find.byWidgetPredicate(
      (w) => w is Container && (w.decoration as BoxDecoration?)?.color == pick,
    );
    expect(dots, findsNWidgets(2));
    for (var i = 0; i < dots.evaluate().length; i++) {
      if (tester.getSize(dots.at(i)) == const Size(34, 34)) {
        await tester.tap(dots.at(i));
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(store.scoreColorValue(-1), 0xFF1B5E20);
  });


}
