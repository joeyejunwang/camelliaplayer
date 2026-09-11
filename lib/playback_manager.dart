import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'subtitle_loader.dart';

/// Singleton that owns the shared [Player] instance and exposes its
/// streams as ChangeNotifier state so any widget can react to playback.
class PlaybackManager extends ChangeNotifier {
  PlaybackManager._();

  static final PlaybackManager instance = PlaybackManager._();

  Player? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<void>? _completedSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isMuted = false;
  double _volume = 1.0;
  bool _hasMedia = false;
  String _mediaTitle = 'No media playing';
  bool _repeatLyric = false;
  bool _showSubtitleTrack = true;
  bool _showLyric = true;
  VoidCallback? onPlayPreviousLyric;
  VoidCallback? onPlayNextLyric;
  VoidCallback? onPlayFirstLyric;
  VoidCallback? onPlayLastLyric;

  /// The active subtitle list pushed in by the player screen once it has
  /// finished loading the .srt file. Used by [_maybeAdvanceLyric] to walk
  /// through every lyric one by one when repeat-lyric is off.
  List<SubtitleEntry> _subtitles = const [];

  // When [_repeatLyric] is on and a segment is set, the position listener
  // snaps the playhead back to [_loopStart] once the playhead crosses
  // [_loopEnd]. With only [_loopStart] set (no end), the track-completion
  // listener is the fallback — useful when the lyric carries no explicit
  // end timestamp.
  Duration? _loopStart;
  Duration? _loopEnd;

  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  bool get hasMedia => _hasMedia;
  String get mediaTitle => _mediaTitle;
  bool get repeatLyric => _repeatLyric;
  bool get showSubtitleTrack => _showSubtitleTrack;
  bool get showLyric => _showLyric;
  List<SubtitleEntry> get subtitles => _subtitles;
  bool get hasSubtitles => _subtitles.isNotEmpty;

  int get currentLyricIndex {
    if (_subtitles.isEmpty) return -1;
    for (int i = _subtitles.length - 1; i >= 0; i--) {
      if (_position >= _subtitles[i].start) return i;
    }
    return -1;
  }

  double get progress => _duration.inMilliseconds > 0
      ? _position.inMilliseconds / _duration.inMilliseconds
      : 0.0;

  Player get player {
    if (_player == null) {
      _player = Player();
      _listenToPlayer();
    }
    return _player!;
  }

  void _listenToPlayer() {
    final p = _player!;
    _positionSub = p.stream.position.listen((pos) {
      _position = pos;
      _maybeLoopSegment();
      notifyListeners();
    });
    _durationSub = p.stream.duration.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
    _playingSub = p.stream.playing.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });
    _volumeSub = p.stream.volume.listen((vol) {
      _volume = vol / 100.0;
      _isMuted = vol == 0;
      notifyListeners();
    });
    _completedSub = p.stream.completed.listen((_) {
      if (_repeatLyric) {
        final target = _loopStart ?? Duration.zero;
        seek(target);
        if (!_isPlaying) play();
      } else {
        _position = Duration.zero;
        notifyListeners();
      }
    });
  }

  Future<void> setMedia(Media media, {String? title}) async {
    _hasMedia = true;
    _mediaTitle = title ?? media.uri.toString();
    _position = Duration.zero;
    _duration = Duration.zero;
    _repeatLyric = false;
    _showSubtitleTrack = true;
    _showLyric = true;
    _loopStart = null;
    _loopEnd = null;
    notifyListeners();
    await player.open(media);
  }

  /// Push the loaded subtitle list into the manager so the auto-advance
  /// logic can walk through every lyric. Call this from the player screen
  /// once the .srt file has finished parsing.
  void setSubtitles(List<SubtitleEntry> subs) {
    _subtitles = subs;
  }

  void setTitle(String title) {
    _mediaTitle = title;
    notifyListeners();
  }

  void setVolume(double vol) {
    player.setVolume(vol * 100);
    _volume = vol.clamp(0.0, 1.0);
    _isMuted = vol == 0;
    notifyListeners();
  }

  void toggleMute() {
    if (_isMuted) {
      player.setVolume(_volume > 0 ? _volume * 100 : 50);
    } else {
      player.setVolume(0);
    }
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void play() => player.play();
  void pause() => player.pause();

  /// Safe [seek] that no-ops if media isn't open yet. media_kit's underlying
  /// Player surfaces a Future error if `seek` is called before `open`
  /// resolves (or if the player has been disposed), and that error would
  /// otherwise bubble up as an uncaught async exception during widget
  /// lifecycle hooks like didUpdateWidget → setLyricLoopSegment.
  void seek(Duration d) {
    if (!_hasMedia) return;
    // Swallow any error from the underlying media_kit call so a failed
    // seek never crashes the UI; playback will resume from the next valid
    // position tick.
    player.seek(d).catchError((_) {});
  }

  void togglePlay() {
    player.playOrPause();
  }

  void playPreviousLyric() => onPlayPreviousLyric?.call();
  void playNextLyric() => onPlayNextLyric?.call();
  void playFirstLyric() => onPlayFirstLyric?.call();
  void playLastLyric() => onPlayLastLyric?.call();

  void toggleRepeatLyric() {
    _repeatLyric = !_repeatLyric;
    notifyListeners();
    // If we're enabling repeat at the end of the track, kick playback off.
    if (_repeatLyric && !_isPlaying && _hasMedia) {
      seek(_loopStart ?? Duration.zero);
      play();
    }
  }

  void toggleShowLyric() {
    _showLyric = !_showLyric;
    notifyListeners();
  }

  void toggleShowSubtitleTrack() {
    _showSubtitleTrack = !_showSubtitleTrack;
    final player = _player;
    if (player == null) {
      notifyListeners();
      return;
    }
    if (_showSubtitleTrack) {
      final tracks = player.state.tracks;
      final firstSub = tracks.subtitle.isNotEmpty
          ? tracks.subtitle.first
          : null;
      if (firstSub != null) player.setSubtitleTrack(firstSub);
    } else {
      player.setSubtitleTrack(SubtitleTrack('no', null, null));
    }
    notifyListeners();
  }

  /// Detail screen calls this as the active lyric changes. When
  /// [_repeatLyric] is on, the player will loop the [start, end] window.
  /// Pass null for either side to clear that bound (e.g. on dispose).
  ///
  /// This method never seeks — looping is handled by [_maybeLoopSegment]
  /// reacting to position ticks, which avoids throwing when media isn't
  /// ready yet and avoids re-snapping the playhead every time the active
  /// lyric updates.
  void setLyricLoopSegment({Duration? start, Duration? end}) {
    _loopStart = start;
    _loopEnd = end;
  }

  /// Position-tick hook. When [_repeatLyric] is on, snap the playhead back
  /// to [_loopStart] once the playhead crosses [_loopEnd] (loop-one
  /// behaviour). When [_repeatLyric] is off and subtitles are loaded,
  /// walk through every lyric one by one: when the current lyric ends,
  /// seek to the next lyric's start and keep playing. After the last
  /// lyric, wrap back to the first.
  void _maybeLoopSegment() {
    if (_repeatLyric) {
      final start = _loopStart;
      final end = _loopEnd;
      if (start == null) return;
      if (end != null && end > start && _position >= end) {
        seek(start);
      }
      return;
    }
    _maybeAdvanceLyric();
  }

  /// Auto-advance through every lyric in [_subtitles]. Finds the latest
  /// lyric whose start is at or before the current position; if the
  /// playhead has already crossed that lyric's end, jump to the next
  /// lyric's start. Only runs while playing so a paused position never
  /// surprises the user with a seek.
  void _maybeAdvanceLyric() {
    if (_subtitles.isEmpty) return;
    if (!_isPlaying) return;
    final subs = _subtitles;

    int idx = -1;
    for (int i = subs.length - 1; i >= 0; i--) {
      if (subs[i].start <= _position) {
        idx = i;
        break;
      }
    }
    if (idx < 0) return;

    final current = subs[idx];
    if (_position >= current.end) {
      final nextIdx = (idx + 1) % subs.length;
      final next = subs[nextIdx];
      _loopStart = next.start;
      _loopEnd = nextIdx + 1 < subs.length ? subs[nextIdx + 1].start : null;
      seek(next.start);
    } else {
      _loopStart = current.start;
      _loopEnd = idx + 1 < subs.length ? subs[idx + 1].start : null;
    }
  }

  void stop() {
    _hasMedia = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _repeatLyric = false;
    _showSubtitleTrack = true;
    _showLyric = true;
    _loopStart = null;
    _loopEnd = null;
    player.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _volumeSub?.cancel();
    _completedSub?.cancel();
    _player?.dispose();
    _player = null;
    super.dispose();
  }
}
