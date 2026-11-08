import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_player/playback_manager.dart';

void main() {
  test('player mode menu includes Talking', () {
    expect(PlayerMode.values, contains(PlayerMode.talking));
    expect(PlayerMode.talking.label, 'Talking');
    expect(PlayerMode.values[1], PlayerMode.talking);
  });

  test('Talking pause follows lyric duration within practical bounds', () {
    expect(
      PlaybackManager.talkingPauseDuration(const Duration(seconds: 1)),
      const Duration(seconds: 2),
    );
    expect(
      PlaybackManager.talkingPauseDuration(const Duration(seconds: 4)),
      const Duration(seconds: 4),
    );
    expect(
      PlaybackManager.talkingPauseDuration(const Duration(seconds: 15)),
      const Duration(seconds: 10),
    );
  });

  test('Talking mode can show and hide the side lyrics', () {
    final manager = PlaybackManager.instance;
    manager.setPlayerMode(PlayerMode.talking);
    expect(manager.showLyric, isFalse);

    manager.toggleShowLyric();
    expect(manager.showLyric, isTrue);
    manager.toggleShowLyric();
    expect(manager.showLyric, isFalse);

    manager.setPlayerMode(PlayerMode.listening);
    expect(manager.showLyric, isTrue);
  });
}
