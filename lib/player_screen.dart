import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'custom_title_bar.dart';
import 'mini_player.dart';
import 'playback_manager.dart';
import 'subtitle_loader.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.videoFile,
    required this.videoPath,
    required this.videoName,
    this.subtitleFile,
    this.subtitlePath,
  });

  final File? videoFile;
  final String? videoPath;
  final String videoName;
  final File? subtitleFile;
  final String? subtitlePath;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoController _videoController;
  List<SubtitleEntry> _subtitles = const [];
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  final ScrollController _lyricsScrollController = ScrollController();
  int? _lastScrolledIndex;

  bool get _isMp3 =>
      p
              .extension(
                widget.videoFile?.path ?? widget.videoPath ?? widget.videoName,
              )
              .toLowerCase() ==
          '.mp3' ||
      p
              .extension(
                widget.videoFile?.path ?? widget.videoPath ?? widget.videoName,
              )
              .toLowerCase() ==
          '.wav' ||
      p
              .extension(
                widget.videoFile?.path ?? widget.videoPath ?? widget.videoName,
              )
              .toLowerCase() ==
          '.aac';

  @override
  void initState() {
    super.initState();
    final pm = PlaybackManager.instance;
    _videoController = VideoController(pm.player);

    pm.onPlayPreviousLyric = () => _stepLyric(-1);
    pm.onPlayNextLyric = () => _stepLyric(1);
    pm.onPlayFirstLyric = () => _seekToSubtitleIndex(0);
    pm.onPlayLastLyric = () => _seekToSubtitleIndex(_subtitles.length - 1);

    _bootstrap();
    _positionSub = pm.player.stream.position.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
      _scrollToCurrent();
    });
  }

  /// Open the video, load its sibling .srt (if any), then start playback.
  /// Going through media first guarantees the playhead is parked at a
  /// real timestamp before we seek to the first lyric; loading the
  /// subtitle file separately (and synchronously after open) lets
  /// auto-advance see the full lyric list the moment the user picks the
  /// video.
  Future<void> _bootstrap() async {
    await _openMedia();
    await _loadSubtitles();
    // No companion .srt was found — just start playback from the top
    // so the user doesn't get a frozen black frame after picking a video.
    if (widget.subtitleFile == null && mounted) {
      PlaybackManager.instance.play();
    }
  }

  Future<void> _openMedia() async {
    final pm = PlaybackManager.instance;
    final dir = p.dirname(Platform.resolvedExecutable);

    if (widget.videoFile != null) {
      final path = p.isAbsolute(widget.videoFile!.path)
          ? widget.videoFile!.path
          : p.join(dir, widget.videoFile!.path);
      await pm.setMedia(Media(path), title: widget.videoName);
    } else if (widget.videoPath != null) {
      final path = p.isAbsolute(widget.videoPath!)
          ? widget.videoPath!
          : p.join(dir, widget.videoPath!);
      await pm.setMedia(Media(path), title: widget.videoName);
    }
  }

  Future<void> _loadSubtitles() async {
    if (widget.subtitleFile == null) return;
    try {
      final dir = p.dirname(Platform.resolvedExecutable);
      final path = p.isAbsolute(widget.subtitleFile!.path)
          ? widget.subtitleFile!.path
          : p.join(dir, widget.subtitleFile!.path);
      final loaded = await SubtitleLoader.loadFromFile(File(path));
      if (!mounted) return;
      setState(() => _subtitles = loaded);
      // Now that the full lyric list is here, hand it to the manager and
      // jump to the first lyric before the player starts bleeding through
      // its intro. This is the spot the user expects: pick the video,
      // and the first lyric plays immediately.
      final pm = PlaybackManager.instance;
      pm.setSubtitles(loaded);
      if (pm.hasMedia) {
        pm.playFirstLyric();
      }
      pm.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  int? get _currentIndex {
    for (int i = 0; i < _subtitles.length; i++) {
      if (_subtitles[i].textAt(_position) != null) return i;
    }
    return null;
  }

  void _seekToSubtitleIndex(int index) {
    if (index < 0 || index >= _subtitles.length) return;
    _seekToEntry(_subtitles[index]);
  }

  /// Step [direction] (+1 = next, -1 = previous) through the lyric list.
  /// When the playhead is currently inside a lyric the step is taken
  /// relative to that cue; otherwise we fall back to the playhead itself
  /// so a paused or boundary playhead still lands on the correct cue
  /// instead of silently snapping back to the start of the song.
  ///
  /// This matters especially for short cues: when a cue is shorter than
  /// the gap between two position ticks, the playhead can be exactly
  /// between two cues at the moment the user hits the key. The old
  /// `(_currentIndex ?? 0) + 1` fallback would then jump to subs[1],
  /// which looks like the song is playing from the beginning. Using the
  /// playhead as the anchor makes the next/previous step always land on
  /// the cue that is actually adjacent to the current position, and
  /// wraps cleanly past either end of the list.
  void _stepLyric(int direction) {
    final subs = _subtitles;
    if (subs.isEmpty) return;
    final cur = _currentIndex;
    int targetIdx;
    if (cur != null) {
      // Dart's `%` returns a non-negative result for a positive divisor,
      // so this wraps automatically at either end of the list.
      targetIdx = (cur + direction) % subs.length;
    } else {
      // No active cue — playhead sits between cues, before the first
      // one, or past the last one. Anchor on the playhead itself.
      final pos = _position;
      if (direction > 0) {
        targetIdx = 0;
        for (int i = 0; i < subs.length; i++) {
          if (subs[i].start > pos) {
            targetIdx = i;
            break;
          }
        }
      } else {
        targetIdx = subs.length - 1;
        for (int i = subs.length - 1; i >= 0; i--) {
          if (subs[i].end < pos) {
            targetIdx = i;
            break;
          }
        }
      }
    }
    _seekToSubtitleIndex(targetIdx);
  }

  void _scrollToCurrent() {
    if (!PlaybackManager.instance.showLyric) return;
    final idx = _currentIndex;
    if (idx == null || !_lyricsScrollController.hasClients) return;
    if (idx == _lastScrolledIndex) return;
    _lastScrolledIndex = idx;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_lyricsScrollController.hasClients) return;
      const itemHeight = 56.0;
      final viewportHeight = _lyricsScrollController.position.viewportDimension;
      final offset = idx * itemHeight - (viewportHeight / 2) + (itemHeight / 2);
      final maxScroll = _lyricsScrollController.position.maxScrollExtent;
      _lyricsScrollController.animateTo(
        offset.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _seekToEntry(SubtitleEntry entry) {
    final pm = PlaybackManager.instance;
    final idx = _subtitles.indexOf(entry);
    final nextEntry = (idx >= 0 && idx + 1 < _subtitles.length)
        ? _subtitles[idx + 1]
        : null;
    pm.setLyricLoopSegment(start: entry.start, end: nextEntry?.start);
    pm.seek(entry.start);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final pm = PlaybackManager.instance;
    final hasMedia = pm.hasMedia;

    void noop() {}

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): hasMedia
            ? () => pm.togglePlay()
            : noop,
        const SingleActivator(LogicalKeyboardKey.home): hasMedia
            ? () => pm.playFirstLyric()
            : noop,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): hasMedia
            ? () => pm.playPreviousLyric()
            : noop,
        const SingleActivator(LogicalKeyboardKey.arrowRight): hasMedia
            ? () => pm.playNextLyric()
            : noop,
        const SingleActivator(LogicalKeyboardKey.end): hasMedia
            ? () => pm.playLastLyric()
            : noop,
        const SingleActivator(LogicalKeyboardKey.keyR): hasMedia
            ? () => pm.toggleRepeatLyric()
            : noop,
        const SingleActivator(LogicalKeyboardKey.keyL): () =>
            pm.toggleShowLyric(),
        const SingleActivator(LogicalKeyboardKey.arrowUp): hasMedia
            ? () => pm.setVolume((pm.volume + 0.1).clamp(0.0, 1.0))
            : noop,
        const SingleActivator(LogicalKeyboardKey.arrowDown): hasMedia
            ? () => pm.setVolume((pm.volume - 0.1).clamp(0.0, 1.0))
            : noop,
        const SingleActivator(LogicalKeyboardKey.keyS): hasMedia
            ? () => pm.toggleShowSubtitleTrack()
            : noop,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF0F0F12),
          body: Column(
            children: [
              const CustomTitleBar(),
              Expanded(
                child: Row(
                  children: [
                    // ── Video area ──────────────────────────────────────────────
                    Expanded(
                      flex: 65,
                      child: Stack(
                        children: [
                          // Video or audio artwork
                          Positioned.fill(
                            child: Center(
                              child: _isMp3
                                  ? Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.music_note_rounded,
                                            size: 80,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            widget.videoName,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Video(
                                      controller: _videoController,
                                      controls: NoVideoControls,
                                    ),
                            ),
                          ),

                          // Centered lyric overlay for audio-only playback
                          // (.wav / .mp3 / .aac). Shown only while the
                          // subtitle (S) toggle is on and a lyric cue is
                          // active at the current playhead position so the
                          // user gets karaoke-style feedback on top of the
                          // audio artwork.
                          if (_isMp3 &&
                              PlaybackManager.instance.showSubtitleTrack &&
                              _currentIndex != null)
                            Positioned(
                              top: 12,
                              left: 16,
                              right: 16,
                              child: IgnorePointer(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black
                                        .withValues(alpha: 0.55),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _subtitles[_currentIndex!].text,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Floating back button
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                onTap: () => Navigator.of(context).pop(),
                                borderRadius: BorderRadius.circular(20),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Lyrics toggle button
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                onTap: () =>
                                    PlaybackManager.instance.toggleShowLyric(),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    PlaybackManager.instance.showLyric
                                        ? Icons.view_sidebar
                                        : Icons.view_sidebar_outlined,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Lyrics panel ───────────────────────────────────────────
                    if (PlaybackManager.instance.showLyric)
                      SizedBox(
                        width: 340,
                        child: _LyricsPanel(
                          subtitles: _subtitles,
                          currentIndex: _currentIndex,
                          scrollController: _lyricsScrollController,
                          onSeek: _seekToEntry,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: const MiniPlayerBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Lyrics panel ────────────────────────────────────────────────────────────

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({
    required this.subtitles,
    required this.currentIndex,
    required this.scrollController,
    required this.onSeek,
  });

  final List<SubtitleEntry> subtitles;
  final int? currentIndex;
  final ScrollController scrollController;
  final void Function(SubtitleEntry) onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Panel header
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lyrics_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Lyrics',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  subtitles.isEmpty
                      ? ''
                      : currentIndex == null || currentIndex == -1
                      ? ''
                      : '${currentIndex! + 1} / ${subtitles.length} lines',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Lyrics list
          Expanded(
            child: subtitles.isEmpty
                ? Center(
                    child: Text(
                      'No lyrics loaded',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: subtitles.length,
                    itemExtent: 56,
                    itemBuilder: (context, index) {
                      final entry = subtitles[index];
                      final isActive = index == currentIndex;

                      return _LyricLine(
                        entry: entry,
                        isActive: isActive,
                        onTap: () => onSeek(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LyricLine extends StatelessWidget {
  const _LyricLine({
    required this.entry,
    required this.isActive,
    required this.onTap,
  });

  final SubtitleEntry entry;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          entry.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isActive
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            fontSize: isActive ? 14 : 13,
          ),
        ),
      ),
    );
  }
}
