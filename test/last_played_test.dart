import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_player/last_played.dart';

void main() {
  test('LastPlayed preserves the lyric index in JSON', () {
    final timestamp = DateTime.utc(2026, 9, 11, 12, 30);
    final original = LastPlayed(
      path: '/media/test.mp4',
      name: 'test.mp4',
      timestamp: timestamp,
      lyricIndex: 42,
    );

    final restored = LastPlayed.fromJson(original.toJson());

    expect(restored.path, original.path);
    expect(restored.name, original.name);
    expect(restored.timestamp, timestamp);
    expect(restored.lyricIndex, 42);
  });

  test('LastPlayed accepts older records without a lyric index', () {
    final restored = LastPlayed.fromJson({
      'path': '/media/test.mp4',
      'name': 'test.mp4',
      'timestamp': '2026-09-11T12:30:00.000Z',
    });

    expect(restored.lyricIndex, isNull);
  });
}
