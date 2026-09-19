import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_player/last_played.dart';

void main() {
  test('LastPlayed preserves the lyric index in JSON', () {
    final original = LastPlayed(
      path: '/media/test.mp4',
      name: 'test.mp4',
      lyricIndex: 42,
    );

    final restored = LastPlayed.fromJson(original.toJson());

    expect(restored.path, original.path);
    expect(restored.name, original.name);
    expect(restored.lyricIndex, 42);
  });

  test('LastPlayed accepts older records without a lyric index', () {
    final restored = LastPlayed.fromJson({
      'path': '/media/test.mp4',
      'name': 'test.mp4',
    });

    expect(restored.lyricIndex, isNull);
  });
}
