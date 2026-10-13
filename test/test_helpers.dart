import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghin_golf/main.dart';
import 'package:ghin_golf/store.dart';

Future<void> pumpTallHome(WidgetTester tester, GolfStore store) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(GhinApp(store: store));
  await tester.pumpAndSettle();
}

Future<void> chooseHoleCount(
  WidgetTester tester, {
  required String selectorKey,
  required int count,
}) async {
  await tester.tap(find.byKey(ValueKey(selectorKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('$count Holes').last);
  await tester.pumpAndSettle();
}