import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_player/playback_manager.dart';

void main() {
  test('player mode menu includes Talking', () {
    expect(PlayerMode.values, contains(PlayerMode.talking));
    expect(PlayerMode.talking.label, 'Talking');
    expect(PlayerMode.values[1], PlayerMode.talking);
  });

  test('Talking recording is limited to four minutes', () {
    expect(PlaybackManager.talkingRecordingLimit, const Duration(minutes: 4));
  });

  test('Talking mode can show and hide the side lyrics', () {
    final manager = PlaybackManager.instance;
    manager.setPlayerMode(PlayerMode.talking);
    expect(manager.showLyric, isTrue);

    manager.toggleShowLyric();
    expect(manager.showLyric, isFalse);
    manager.toggleShowLyric();
    expect(manager.showLyric, isTrue);

    manager.setPlayerMode(PlayerMode.listening);
    expect(manager.showLyric, isTrue);
  });

  test('Talking mode can show and hide the subtitle track', () {
    final manager = PlaybackManager.instance;
    manager.setPlayerMode(PlayerMode.talking);
    expect(manager.showSubtitleTrack, isTrue);

    manager.toggleShowSubtitleTrack();
    expect(manager.showSubtitleTrack, isFalse);
    manager.toggleShowSubtitleTrack();
    expect(manager.showSubtitleTrack, isTrue);

    manager.setPlayerMode(PlayerMode.listening);
    expect(manager.showSubtitleTrack, isTrue);
  });
}
