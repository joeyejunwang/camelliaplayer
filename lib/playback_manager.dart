import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'subtitle_loader.dart';

/// Defines how lyrics are repeated during playback. The [times] value
/// (when not null) is the number of times the current lyric is played
/// before advancing to the next lyric. A null [times] means the current
/// lyric loops forever without ever advancing.
enum LyricRepeatMode {
  /// No repeat logic: each lyric plays once and the player auto-advances
  /// to the next (equivalent to [repeatOne] semantically, but signals
  /// "do not loop" intent).
  noRepeat(times: 1),

  /// Play the current lyric exactly once, then advance to the next.
  repeatOne(times: 1),

  /// Play the current lyric exactly twice, then advance to the next.
  repeatTwo(times: 2),

  /// Play the current lyric exactly three times, then advance to the next.
  repeatThree(times: 3),

  /// Loop the current lyric indefinitely (default).
  repeatAll(times: null);

  const LyricRepeatMode({required this.times});

  /// Number of times the current lyric should be played before advancing.
  /// `null` means loop forever without advancing.
  final int? times;

  /// Human-readable label used in the dropdown.
  String get label {
    switch (this) {
      case LyricRepeatMode.noRepeat:
        return 'No repeat';
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
      case LyricRepeatMode.noRepeat:
        return 'Off';
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
  LyricRepeatMode _repeatMode = LyricRepeatMode.repeatAll;
  bool _showSubtitleTrack = true;
  bool _showLyric = true;
  int _currentLyricRepeatCount = 0;
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
      if (_repeatMode == LyricRepeatMode.repeatAll) {
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
    _repeatMode = LyricRepeatMode.repeatAll;
    _showSubtitleTrack = true;
    _showLyric = true;
    _loopStart = null;
    _loopEnd = null;
    _currentLyricRepeatCount = 0;
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

  /// Seek to the start of the first lyric and start playing. Awaits the
  /// underlying seek so a subsequent `play()` doesn't race ahead and
  /// start playback from position 0. Used when a file is opened — the
  /// user expects the first lyric, not the intro, to play immediately.
  Future<void> jumpToFirstLyricAndPlay() async {
    onPlayFirstLyric?.call();
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
    try {
      await _player?.seek(subs[safe].start);
    } catch (_) {}
    if (!_isPlaying) await _player?.play();
  }

  /// Same as [jumpToFirstLyricAndPlay] but only seeks + plays — used
  /// when the seek callback isn't bound yet. Awaits the underlying
  /// seek so playback begins at the lyric timestamp, not from 0.
  Future<void> seekFirstLyricAndPlay() async {
    final subs = _subtitles;
    if (subs.isEmpty || !_hasMedia) return;
    try {
      await _player?.seek(subs.first.start);
    } catch (_) {}
    if (!_isPlaying) await _player?.play();
  }

  /// Sets the lyric repeat mode directly (used by the dropdown).
  void setRepeatMode(LyricRepeatMode mode) {
    if (_repeatMode == mode) return;
    _repeatMode = mode;
    _currentLyricRepeatCount = 0;
    notifyListeners();
    // If we're enabling repeatAll at the end of the track, kick playback off.
    if (_repeatMode == LyricRepeatMode.repeatAll && !_isPlaying && _hasMedia) {
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
  }

  /// Position-tick hook. Handles:
  /// - repeatAll: snap playhead back to [_loopStart] when it crosses [_loopEnd]
  /// - any other mode with [LyricRepeatMode.times] set: play current lyric
  ///   that many times then advance to next lyric
  /// - noRepeat: auto-advance through every lyric one by one
  void _maybeLoopSegment() {
    if (_repeatMode == LyricRepeatMode.repeatAll) {
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
  /// playhead has already crossed that lyric's end, handle repeat logic
  /// based on current mode. Only runs while playing so a paused position
  /// never surprises the user with a seek.
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
      final required = _repeatMode.times;
      if (required != null && required > 1) {
        // Loop current lyric N times total before advancing.
        _currentLyricRepeatCount++;
        if (_currentLyricRepeatCount < required) {
          seek(current.start);
          return;
        }
        _currentLyricRepeatCount = 0;
      }

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
    _repeatMode = LyricRepeatMode.repeatAll;
    _showSubtitleTrack = true;
    _showLyric = true;
    _loopStart = null;
    _loopEnd = null;
    _currentLyricRepeatCount = 0;
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
