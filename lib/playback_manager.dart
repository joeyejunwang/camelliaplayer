import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'subtitle_loader.dart';

/// Defines how lyrics are repeated during playback. The [times] value
/// (when not null) is the number of times the current lyric is played
/// before advancing to the next lyric. A null [times] means the current
/// lyric loops forever without ever advancing.
enum LyricRepeatMode {
  /// Play the current lyric exactly once, then advance to the next.
  repeatOne(times: 1),

  /// Play the current lyric exactly twice, then advance to the next.
  repeatTwo(times: 2),

  /// Play the current lyric exactly three times, then advance to the next.
  repeatThree(times: 3),

  /// Loop the current lyric indefinitely.
  repeatAll(times: null);

  const LyricRepeatMode({required this.times});

  /// Number of times the current lyric should be played before advancing.
  /// `null` means loop forever without advancing.
  final int? times;

  /// Human-readable label used in the dropdown.
  String get label {
    switch (this) {
      case LyricRepeatMode.repeatOne:
        return 'Repeat 1× then next lyric 1×';
      case LyricRepeatMode.repeatTwo:
        return 'Repeat 2× then next lyric 2×';
      case LyricRepeatMode.repeatThree:
        return 'Repeat 3× then next lyric 3×';
      case LyricRepeatMode.repeatAll:
        return 'Repeat every lyric forever';
    }
  }

  /// Short label used on the mini-player trigger button.
  String get shortLabel {
    switch (this) {
      case LyricRepeatMode.repeatOne:
        return '×1';
      case LyricRepeatMode.repeatTwo:
        return '×2';
      case LyricRepeatMode.repeatThree:
        return '×3';
      case LyricRepeatMode.repeatAll:
        return '∞';
    }
  }
}

/// The selected player mode. Mode-specific playback behavior can be added
/// without changing how the transport controls are wired.
enum PlayerMode {
  listening('Listening'),
  marking('Marking'),
  testing('Testing');

  const PlayerMode(this.label);

  final String label;
}

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
  StreamSubscription<bool>? _completedSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isMuted = false;
  double _volume = 1.0;
  double _lastAudibleVolume = 1.0;
  bool _hasMedia = false;
  String _mediaTitle = 'No media playing';
  LyricRepeatMode _repeatMode = LyricRepeatMode.repeatTwo;
  PlayerMode _playerMode = PlayerMode.listening;
  bool _showSubtitleTrack = true;
  bool _showLyric = true;
  int _currentLyricRepeatCount = 0;
  int? _repeatLyricIndex;
  Duration? _automaticSeekTarget;
  int _seekRevision = 0;
  VoidCallback? onPlayPreviousLyric;
  VoidCallback? onPlayNextLyric;
  VoidCallback? onPlayFirstLyric;
  VoidCallback? onPlayLastLyric;

  /// The active subtitle list pushed in by the player screen once it has
  /// finished loading the .srt file. Used by [_maybeAdvanceLyric] to walk
  /// through every lyric one by one when repeat-lyric is off.
  List<SubtitleEntry> _subtitles = const [];

  // When [_repeatMode] is repeatAll and a segment is set, the position listener
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
  LyricRepeatMode get repeatMode => _repeatMode;
  PlayerMode get playerMode => _playerMode;
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
      final target = _automaticSeekTarget;
      if (target != null) {
        // Ignore old position ticks until the automatic seek has landed.
        // Otherwise a short cue can count the same boundary several times.
        if ((pos - target).abs() <= const Duration(milliseconds: 250)) {
          _automaticSeekTarget = null;
        }
      } else {
        _maybeLoopSegment();
      }
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
      if (vol > 0) _lastAudibleVolume = _volume;
      notifyListeners();
    });
    _completedSub = p.stream.completed.listen((completed) {
      if (!completed) return;
      if (_repeatMode == LyricRepeatMode.repeatAll) {
        final target = _loopStart ?? Duration.zero;
        _seekAutomatically(target, resume: true);
      } else {
        _repeatLyricIndex = null;
        _currentLyricRepeatCount = 0;
        _position = Duration.zero;
        notifyListeners();
      }
    });
  }

  Future<void> setMedia(Media media, {String? title}) async {
    _hasMedia = false;
    _mediaTitle = title ?? media.uri.toString();
    _position = Duration.zero;
    _duration = Duration.zero;
    _repeatMode = LyricRepeatMode.repeatTwo;
    _playerMode = PlayerMode.listening;
    _showSubtitleTrack = true;
    _showLyric = true;
    _loopStart = null;
    _loopEnd = null;
    _currentLyricRepeatCount = 0;
    _repeatLyricIndex = null;
    _automaticSeekTarget = null;
    _seekRevision++;
    _subtitles = const [];
    notifyListeners();
    await player.open(media, play: false);
    _hasMedia = true;
    notifyListeners();
    // Opening paused keeps the intro silent until the first or resumed
    // lyric has been selected and an explicit play() begins.
  }

  /// Push the loaded subtitle list into the manager so the auto-advance
  /// logic can walk through every lyric. Call this from the player screen
  /// once the .srt file has finished parsing.
  void setSubtitles(List<SubtitleEntry> subs) {
    _subtitles = subs;
    _currentLyricRepeatCount = 0;
    _repeatLyricIndex = null;
    notifyListeners();
  }

  void setTitle(String title) {
    _mediaTitle = title;
    notifyListeners();
  }

  void setVolume(double vol) {
    player.setVolume(vol * 100);
    _volume = vol.clamp(0.0, 1.0);
    _isMuted = vol == 0;
    if (vol > 0) _lastAudibleVolume = _volume;
    notifyListeners();
  }

  void toggleMute() {
    if (_isMuted) {
      setVolume(_lastAudibleVolume);
    } else {
      setVolume(0);
    }
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
    _currentLyricRepeatCount = 0;
    _repeatLyricIndex = null;
    _automaticSeekTarget = null;
    _seekRevision++;
    _setLoopForPosition(d);
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

  /// Seek to the start of the first lyric and start playing. Awaits the
  /// underlying seek so a subsequent `play()` doesn't race ahead and
  /// start playback from position 0. Used when a file is opened — the
  /// user expects the first lyric, not the intro, to play immediately.
  Future<void> jumpToFirstLyricAndPlay() async {
    await seekFirstLyricAndPlay();
  }

  /// Seek to the start of the lyric at [index] and start playing. Used
  /// when resuming a file from a saved cue (e.g. the "last played"
  /// card on the home screen). Awaits the underlying seek so playback
  /// begins at the lyric timestamp, not from 0.
  Future<void> jumpToLyricIndex(int index) async {
    final subs = _subtitles;
    if (subs.isEmpty || !_hasMedia) return;
    final safe = index.clamp(0, subs.length - 1);
    final p = player;
    // open(play: false) queues the media load. A seek issued before mpv has
    // read the file can be accepted but leave the position at zero.
    final mediaDuration = p.state.duration > Duration.zero
        ? p.state.duration
        : await p.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 10));
    if (!_hasMedia) return;
    final target = subs[safe].start;
    if (target >= mediaDuration && target > Duration.zero) {
      throw StateError('Lyric starts after the end of the media');
    }
    _setLoopForIndex(safe);
    _repeatLyricIndex = safe;
    _currentLyricRepeatCount = 0;
    for (var attempt = 0; attempt < 2; attempt++) {
      final arrived = Completer<void>();
      bool atTarget(Duration position) =>
          (position - target).abs() <= const Duration(milliseconds: 150);
      final subscription = p.stream.position.listen((position) {
        if (atTarget(position) && !arrived.isCompleted) arrived.complete();
      });
      try {
        await p.seek(target);
        if (!_hasMedia) return;
        if (atTarget(p.state.position) && !arrived.isCompleted) {
          arrived.complete();
        }
        await arrived.future.timeout(const Duration(seconds: 3));
        await p.play();
        return;
      } on TimeoutException {
        if (attempt == 1) rethrow;
      } finally {
        await subscription.cancel();
      }
    }
  }

  /// Same as [jumpToFirstLyricAndPlay] but only seeks + plays — used
  /// when the seek callback isn't bound yet. Awaits the underlying
  /// seek so playback begins at the lyric timestamp, not from 0.
  Future<void> seekFirstLyricAndPlay() async {
    await jumpToLyricIndex(0);
  }

  /// Updates the selected player mode without changing playback behavior.
  void setPlayerMode(PlayerMode mode) {
    if (_playerMode == mode) return;
    _playerMode = mode;
    notifyListeners();
  }

  /// Sets the lyric repeat mode directly (used by the dropdown).
  void setRepeatMode(LyricRepeatMode mode) {
    final index = _subtitles.isEmpty
        ? null
        : (_repeatLyricIndex ??
              (currentLyricIndex >= 0 ? currentLyricIndex : 0));
    _repeatMode = mode;
    _currentLyricRepeatCount = 0;
    _repeatLyricIndex = index;
    if (index != null) {
      _setLoopForIndex(index);
    }
    notifyListeners();
    if (index != null && _hasMedia) {
      unawaited(_restartLyric(index));
    }
  }

  Future<void> _restartLyric(int index) async {
    final target = _subtitles[index].start;
    final revision = ++_seekRevision;
    _automaticSeekTarget = target;
    try {
      await player.seek(target);
      if (revision == _seekRevision && _hasMedia) {
        await player.play();
      }
    } catch (_) {
      if (revision == _seekRevision) {
        _automaticSeekTarget = null;
      }
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
  /// [_repeatMode] is repeatAll, the player will loop the [start, end] window.
  /// Pass null for either side to clear that bound (e.g. on dispose).
  ///
  /// This method never seeks — looping is handled by [_maybeLoopSegment]
  /// reacting to position ticks, which avoids throwing when media isn't
  /// ready yet and avoids re-snapping the playhead every time the active
  /// lyric updates.
  void setLyricLoopSegment({Duration? start, Duration? end}) {
    _loopStart = start;
    _loopEnd = end;
    _currentLyricRepeatCount = 0;
    _repeatLyricIndex = null;
  }

  void _setLoopForIndex(int index) {
    final entry = _subtitles[index];
    final end = index + 1 < _subtitles.length
        ? _subtitles[index + 1].start
        : entry.end;
    _loopStart = entry.start;
    _loopEnd = end > entry.start ? end : null;
  }

  void _setLoopForPosition(Duration position) {
    int index = -1;
    for (int i = _subtitles.length - 1; i >= 0; i--) {
      if (_subtitles[i].start <= position) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      _repeatLyricIndex = null;
      _loopStart = null;
      _loopEnd = null;
    } else {
      _repeatLyricIndex = index;
      _setLoopForIndex(index);
    }
  }

  Future<void> _seekAutomatically(Duration target, {bool resume = false}) async {
    if (!_hasMedia || _automaticSeekTarget != null) return;
    final revision = ++_seekRevision;
    _automaticSeekTarget = target;
    try {
      await player.seek(target);
      if (revision == _seekRevision && resume && !_isPlaying) {
        await player.play();
      }
    } catch (_) {
      if (revision == _seekRevision) {
        _automaticSeekTarget = null;
      }
    }
  }

  /// Position-tick hook. Handles:
  /// - repeatAll: snap playhead back to [_loopStart] when it crosses [_loopEnd]
  /// - any other mode with [LyricRepeatMode.times] set: play current lyric
  ///   that many times then advance to next lyric
  void _maybeLoopSegment() {
    if (_repeatMode == LyricRepeatMode.repeatAll) {
      final start = _loopStart;
      final end = _loopEnd;
      if (start == null) return;
      if (end != null && end > start && _position >= end) {
        _seekAutomatically(start);
      }
      return;
    }
    _maybeAdvanceLyric();
  }

  /// Auto-advance from the selected lyric. Keep its index across automatic
  /// seeks: video decoders can report a position before the requested cue
  /// while seeking to a keyframe, which must not reset the repeat count.
  void _maybeAdvanceLyric() {
    if (_subtitles.isEmpty) return;
    if (!_isPlaying) return;
    final subs = _subtitles;

    var idx = _repeatLyricIndex;
    if (idx == null) {
      for (int i = subs.length - 1; i >= 0; i--) {
        if (subs[i].start <= _position) {
          idx = i;
          _repeatLyricIndex = i;
          break;
        }
      }
    }
    if (idx == null) return;

    final current = subs[idx];
    if (_position < current.start) return;
    if (_position >= current.end) {
      final required = _repeatMode.times;
      if (required != null && required > 1) {
        // Loop current lyric N times total before advancing.
        _currentLyricRepeatCount++;
        if (_currentLyricRepeatCount < required) {
          _seekAutomatically(current.start);
          return;
        }
        _currentLyricRepeatCount = 0;
      }

      final nextIdx = (idx + 1) % subs.length;
      final next = subs[nextIdx];
      _setLoopForIndex(nextIdx);
      _repeatLyricIndex = nextIdx;
      _seekAutomatically(next.start);
    } else {
      _setLoopForIndex(idx);
    }
  }

  void stop() {
    _hasMedia = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _repeatMode = LyricRepeatMode.repeatTwo;
    _playerMode = PlayerMode.listening;
    _showSubtitleTrack = true;
    _showLyric = true;
    _loopStart = null;
    _loopEnd = null;
    _currentLyricRepeatCount = 0;
    _repeatLyricIndex = null;
    _automaticSeekTarget = null;
    _seekRevision++;
    _subtitles = const [];
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
