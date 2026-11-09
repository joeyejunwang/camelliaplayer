import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_player/main.dart';

void main() {
  testWidgets('Library home screen renders its primary controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CamelliaPlayerApp());
    await tester.pump();

    expect(find.text('Camellia Player'), findsOneWidget);
    expect(find.text('ALL VIDEOS'), findsOneWidget);
    expect(find.text('Add Video Folder'), findsOneWidget);
    expect(find.text('Add Video'), findsWidgets);
    expect(find.text('Search videos and folders...'), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Recording source'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('APPID'), findsOneWidget);
    expect(find.text('APIKey'), findsOneWidget);
    expect(find.text('APISecret'), findsOneWidget);
  });
}
