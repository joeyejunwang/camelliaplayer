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
  });
}
