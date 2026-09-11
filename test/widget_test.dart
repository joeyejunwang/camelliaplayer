import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_player/main.dart';

void main() {
  testWidgets('Home screen renders title and picker cards', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CamelliaPlayerApp());
    await tester.pump();

    expect(find.text('Camellia Player'), findsOneWidget);
    expect(find.text('Audio or video file'), findsOneWidget);
    expect(find.text('Pick or drop an .mp4, .wav, .mp3, …'), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
  });
}
