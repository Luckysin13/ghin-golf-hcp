import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/stats_page.dart';
import 'package:ghin_golf/models.dart';
import 'package:ghin_golf/store.dart';
import 'package:ghin_golf/whs.dart' as whs;

void main() {
  testWidgets('Performance no longer advertises driving distance', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: GolfStore())));
    expect(
      find.textContaining(RegExp('driving distance', caseSensitive: false)),
      findsNothing,
    );
  });


  testWidgets('Stats groups scores by expandable course and calculates CH', (
    tester,
  ) async {
    final store = GolfStore();
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
      Course(
        id: 'south',
        name: 'South Course',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'south-white',
            name: 'White',
            rating: 72,
            slope: 113,
            holes: tee.holes,
          ),
        ],
        custom: true,
      ),
    ];
    store.rounds = [
      Round(
        id: 'north-round',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
        handicapIndexAtPlay: 12.4,
      ),
      Round(
        id: 'south-round',
        courseId: 'south',
        teeId: 'south-white',
        playedAt: DateTime(2026, 9, 21),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
        courseHandicap: 7,
      ),
    ];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Courses Played'), findsOneWidget);
    expect(find.text('North Course'), findsOneWidget);
    expect(find.text('South Course'), findsOneWidget);
    expect(find.text('Total: 90 • (F) 45 • (B) 45'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    expect(find.text('Total: 90 • (F) 45 • (B) 45'), findsOneWidget);
    expect(
      find.text('09/20/2026 • 18 holes • Putts 36 • Pen 0'),
      findsOneWidget,
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Total: 72 • (F) 36 • (B) 36'), findsNothing);

    // The header area, including its subtitle, toggles the whole course group.
    await tester.tap(find.text('North Course'));
    await tester.pumpAndSettle();
    expect(find.text('Total: 90 • (F) 45 • (B) 45'), findsNothing);
  });


  testWidgets('Stats course header shows the WHS course handicap', (
    tester,
  ) async {
    final store = GolfStore();
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
    ];
    store.rounds = [
      Round(
        id: 'north-round-1',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
        handicapIndexAtPlay: 12.4,
      ),
      Round(
        id: 'north-round-2',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 21),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
        courseHandicap: 5,
      ),
      Round(
        id: 'north-round-3',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 22),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
        handicapIndexAtPlay: 12.4,
      ),
    ];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    // One handicap for the course from the live index — not a sum — while
    // the per-round avatars stay exactly as they are.
    final hi = store.handicapIndex!;
    final expected = whs.courseHandicap(
      handicapIndex: hi,
      slopeRating: 113,
      courseRating: 72,
      par: 72,
    );
    expect(find.text('3 rounds • CH $expected'), findsOneWidget);
    expect(find.textContaining('Total CH'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    expect(find.text('Total: 90 • (F) 45 • (B) 45'), findsWidgets);
    expect(find.text('Total: 72 • (F) 36 • (B) 36'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(find.text('5'), findsOneWidget);
  });


  testWidgets('Stats course header shows a dash before an index exists', (
    tester,
  ) async {
    final store = GolfStore();
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [
          Tee(
            id: 'white',
            name: 'White',
            rating: 72,
            slope: 113,
            holes: [
              for (var i = 0; i < 18; i++)
                HoleInfo(
                  number: i + 1,
                  par: 4,
                  yardage: 400,
                  strokeIndex: i + 1,
                ),
            ],
          ),
        ],
        custom: true,
      ),
    ];
    store.rounds = [
      Round(
        id: 'north-round-1',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
      ),
    ];
    expect(store.handicapIndex, isNull);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('1 round • CH —'), findsOneWidget);
  });


  testWidgets(
    'Stats avatars backfill from the live index for same-day rounds',
    (tester) async {
      final store = GolfStore();
      final tee = Tee(
        id: 'white',
        name: 'White',
        rating: 72,
        slope: 113,
        holes: [
          for (var i = 0; i < 18; i++)
            HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
        ],
      );
      store.courses = [
        Course(
          id: 'north',
          name: 'North Course',
          city: '',
          state: '',
          tees: [tee],
          custom: true,
        ),
      ];
      // Same calendar day, nothing stored: no round has an index in effect
      // before its own date, but the live index still resolves.
      final day = DateTime(2026, 9, 20);
      store.rounds = [
        for (var n = 0; n < 3; n++)
          Round(
            id: 'north-round-$n',
            courseId: 'north',
            teeId: 'white',
            playedAt: day,
            holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
          ),
      ];
      expect(store.handicapIndexBefore(day), isNull);
      final hi = store.handicapIndex!;
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stats-course-north')));
      await tester.pumpAndSettle();
      final expected = whs.courseHandicap(
        handicapIndex: hi,
        slopeRating: 113,
        courseRating: 72,
        par: 72,
      );
      expect(find.text('$expected'), findsWidgets);
      expect(find.text('—'), findsNothing);
    },
  );


  testWidgets('Stats avatars halve the tee for nines without split ratings', (
    tester,
  ) async {
    final store = GolfStore();
    // No front/back nine rating or slope: the nine-hole formula has nothing
    // to work with, so the avatar must fall back to half the full tee.
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
    ];
    final day = DateTime(2026, 9, 20);
    HoleScore h(int s) => HoleScore(score: s, putts: 2);
    store.rounds = [
      for (var n = 0; n < 3; n++)
        Round(
          id: 'north-round-$n',
          courseId: 'north',
          teeId: 'white',
          playedAt: day,
          holes: [for (var i = 0; i < 18; i++) h(5)],
        ),
      Round(
        id: 'north-nine',
        courseId: 'north',
        teeId: 'white',
        playedAt: day,
        holes: [for (var i = 0; i < 9; i++) h(5)],
      ),
    ];
    final hi = store.handicapIndex!;
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    final full = whs.courseHandicap(
      handicapIndex: hi,
      slopeRating: 113,
      courseRating: 72,
      par: 72,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stats-round-north-nine')),
        matching: find.text('${(full / 2).round()}'),
      ),
      findsOneWidget,
    );
    expect(find.text('—'), findsNothing);
  });


  testWidgets('Stats rounds show a photo icon only when a picture is saved', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('ghin_stats_photo');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // A real decodable PNG: the viewer actually renders these bytes.
    final photo = File('${tmp.path}/r1.png')
      ..writeAsBytesSync(
        File(
          'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
        ).readAsBytesSync(),
      );
    final store = GolfStore();
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
    ];
    Round round(String id, {String img = ''}) => Round(
      id: id,
      courseId: 'north',
      teeId: 'white',
      playedAt: DateTime(2026, 9, 20),
      holes: [for (var i = 0; i < 18; i++) HoleScore(score: 4, putts: 2)],
      courseHandicap: 7,
      imagePath: img,
    );
    store.rounds = [round('r1', img: photo.path), round('r2')];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats-round-photo-r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-round-photo-r2')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stats-round-photo-r1')));
    await tester.pumpAndSettle();
    expect(find.text('North Course — scorecard'), findsOneWidget);
  });


  testWidgets('tapping a Stats round opens its edit page', (tester) async {
    final store = GolfStore();
    final tee = Tee(
      id: 'white',
      name: 'White',
      rating: 72,
      slope: 113,
      holes: [
        for (var i = 0; i < 18; i++)
          HoleInfo(number: i + 1, par: 4, yardage: 400, strokeIndex: i + 1),
      ],
    );
    store.courses = [
      Course(
        id: 'north',
        name: 'North Course',
        city: '',
        state: '',
        tees: [tee],
        custom: true,
      ),
    ];
    store.rounds = [
      Round(
        id: 'north-round',
        courseId: 'north',
        teeId: 'white',
        playedAt: DateTime(2026, 9, 20),
        holes: [for (var i = 0; i < 18; i++) HoleScore(score: 5, putts: 2)],
        handicapIndexAtPlay: 12.4,
      ),
    ];
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stats-course-north')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Total: 90 • (F) 45 • (B) 45'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Round'), findsOneWidget);
  });


}
