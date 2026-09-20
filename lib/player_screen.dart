import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'app_colors.dart';
import 'custom_title_bar.dart';
import 'last_played.dart';
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
    this.initialLyricIndex,
  });

  final File? videoFile;
  final String? videoPath;
  final String videoName;
  final File? subtitleFile;
  final String? subtitlePath;

  /// Optional cue to jump to before starting playback. Used by callers
  /// that resume the user's last position (e.g. the "last played" card
  /// on the home screen). When null, playback starts at the first lyric.
  final int? initialLyricIndex;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoController _videoController;
  List<SubtitleEntry> _subtitles = const [];
  bool _subtitleFileFound = false;
  /// Throttle for the position-driven setState. The player emits
  /// position at the display refresh rate, but humans only need lyric
  /// highlights to update a handful of times per second. Choking the
  /// rebuild rate that low prevents a flood of identical rebuilds
  /// from churning the accessibility tree on Windows ("Failed to
  /// update ui::AXTree" when SemanticsNode ids get recycled
  /// mid-update).
  static const Duration _positionTickMinInterval = Duration(milliseconds: 80);
  DateTime _lastPositionRebuild = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  final ScrollController _lyricsScrollController = ScrollController();
  int? _lastScrolledIndex;
  int? _lastPersistedLyricIndex;
  Future<void> _persistQueue = Future.value();

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
      _position = pos;
      // Always run the cue/scroll logic — it short-circuits when the
      // cue index hasn't changed, so it's cheap even at 60 Hz.
      _scrollToCurrent();
      // Throttle the heavier rebuilds: humans only need lyric
      // highlights to update a handful of times per second, and
      // pushing every position tick into a setState (or a
      // ValueNotifier that drives a build) makes the Windows
      // accessibility bridge throw "Failed to update ui::AXTree"
      // warnings when SemanticsNode ids get recycled mid-update.
      final now = DateTime.now();
      if (now.difference(_lastPositionRebuild) <
          _positionTickMinInterval) {
        return;
      }
      _lastPositionRebuild = now;
      // The setState covers all widgets that read _position in
      // build() — the audio overlay and the lyrics panel. Anything
      // finer-grained would require each subtree to wrap in its own
      // ValueListenableBuilder, which complicates the build for a
      // marginal perf win now that the tick is throttled.
      setState(() {});
    });
  }

  /// Open the video, load its sibling .srt (if any), then start playback.
  /// Going through media first guarantees the playhead is parked at a
  /// real timestamp before we seek to the first lyric; loading the
  /// subtitle file separately (and synchronously after open) lets
  /// auto-advance see the full lyric list the moment the user picks the
  /// video.
  ///
  /// The media is opened paused so the playhead never audibly flashes
  /// through the intro before we land on the first lyric — the user
  /// expects playback to start at the first line, not at 0.
  Future<void> _bootstrap() async {
    try {
      await _openMedia();
      if (!mounted) return;
      await _loadSubtitles();
      if (_subtitles.isEmpty) await _discoverCompanionSubtitle();
      if (!mounted) return;

      final pm = PlaybackManager.instance;
      if (_subtitles.isNotEmpty && pm.hasMedia) {
        await pm.jumpToLyricIndex(_resolveInitialLyricIndex());
      } else if (pm.hasMedia) {
        if (widget.initialLyricIndex != null || _subtitleFileFound) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not load lyrics for this video.'),
          ));
          return;
        }
        pm.play();
      }
    } catch (error) {
      debugPrint('Could not start playback at the lyric: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not seek to the lyric. Playback is paused.'),
      ));
    }
  }

  /// Resolves [widget.initialLyricIndex] to a safe in-range cue index.
  /// Returns 0 (the first lyric) when the caller didn't pass an index,
  /// the recorded index is null, or the saved cue is out of bounds.
  int _resolveInitialLyricIndex() {
    final saved = widget.initialLyricIndex;
    if (saved == null || _subtitles.isEmpty) return 0;
    return saved.clamp(0, _subtitles.length - 1);
  }

  /// Best-effort search for a sibling subtitle file next to the opened
  /// media. Used when the caller did not pass an explicit [subtitleFile].
  /// Tries the exact same basename first, then any subtitle file in the
  /// same directory. If a valid lyric file is found, it is loaded as if
  /// the caller had passed it.
  Future<void> _discoverCompanionSubtitle() async {
    final videoPath =
        widget.videoFile?.path ?? widget.videoPath ?? widget.videoName;
    if (videoPath.isEmpty) return;
    final dir = p.dirname(videoPath);
    final base = videoPath.replaceAll(RegExp(r'\.[^.]+$'), '');
    const exts = ['srt', 'vtt', 'ass', 'ssa'];

    File? found;
    // 1) Exact match: <video>.<ext>
    for (final e in exts) {
      final f = File('$base.$e');
      if (f.existsSync()) {
        found = f;
        break;
      }
    }
    // 2) Any subtitle file in the same folder, prefer the one whose
    //    name shares the longest prefix with the video.
    found ??= await _pickClosestSubtitleIn(dir, base, exts);
    if (found == null) return;
    _subtitleFileFound = true;

    try {
      final loaded = await SubtitleLoader.loadFromFile(found);
      if (!mounted || loaded.isEmpty) return;
      setState(() => _subtitles = loaded);
      PlaybackManager.instance.setSubtitles(loaded);
    } catch (_) {}
  }

  /// Scan [dir] for any file with one of [exts]. Returns the file whose
  /// name shares the longest common prefix with [base], so `song.mp3`
  /// prefers `song.pt.srt` over `other.srt`. Returns null when [dir]
  /// does not exist or has no subtitle files.
  Future<File?> _pickClosestSubtitleIn(
    String dir,
    String base,
    List<String> exts,
  ) async {
    final directory = Directory(dir);
    if (!directory.existsSync()) return null;
    File? best;
    File? onlySubtitle;
    var subtitleCount = 0;
    int bestScore = -1;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path
          .split(Platform.pathSeparator)
          .last
          .toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      final ext = name.substring(dot + 1);
      if (!exts.contains(ext)) continue;
      onlySubtitle = entity;
      subtitleCount++;
      final stem = name.substring(0, dot);
      final baseStem = base
          .split(Platform.pathSeparator)
          .last
          .toLowerCase();
      if (stem != baseStem &&
          !stem.startsWith('$baseStem.') &&
          !stem.startsWith('$baseStem-') &&
          !stem.startsWith('${baseStem}_') &&
          !stem.startsWith('$baseStem ')) {
        continue;
      }
      // Score by shared prefix length so "song.pt" outranks "other".
      var score = 0;
      final max = stem.length < baseStem.length ? stem.length : baseStem.length;
      for (var i = 0; i < max; i++) {
        if (stem[i] != baseStem[i]) break;
        score++;
      }
      if (score > 0 && score > bestScore) {
        bestScore = score;
        best = entity;
      }
    }
    return best ?? (subtitleCount == 1 ? onlySubtitle : null);
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
    _subtitleFileFound = true;
    try {
      final dir = p.dirname(Platform.resolvedExecutable);
      final path = p.isAbsolute(widget.subtitleFile!.path)
          ? widget.subtitleFile!.path
          : p.join(dir, widget.subtitleFile!.path);
      final loaded = await SubtitleLoader.loadFromFile(File(path));
      if (!mounted) return;
      setState(() => _subtitles = loaded);
      // Hand the parsed list to the manager so its auto-advance logic
      // sees it. The seek to the first lyric + play() is owned by
      // _bootstrap so a sibling-discovery fallback runs in the same
      // pass when the explicit subtitle file is missing or empty.
      PlaybackManager.instance.setSubtitles(loaded);
    } catch (_) {}
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _lyricsScrollController.dispose();
    // Best-effort: queue a final write of the cue the playhead is on
    // right now. The back button handler awaits the queue before
    // popping, so in the common case this is a no-op; it covers the
    // window-close and route-teardown paths where no handler fires.
    final idx = _currentIndex;
    if (idx != null) _persistLyricIndex(idx);
    final pm = PlaybackManager.instance;
    pm.onPlayPreviousLyric = null;
    pm.onPlayNextLyric = null;
    pm.onPlayFirstLyric = null;
    pm.onPlayLastLyric = null;
    pm.stop();
    super.dispose();
  }

  int? get _currentIndex {
    for (int i = 0; i < _subtitles.length; i++) {
      if (_subtitles[i].textAt(_position) != null) return i;
    }
    return null;
  }

  /// The lyric line we should keep visually highlighted in the
  /// right-hand lyrics list. This is "sticky" — it remembers the
  /// last cue we were inside even when the playhead sits between
  /// two cues (where [_currentIndex] returns null), so the active
  /// highlight doesn't blink off every gap between lyrics.
  int? _stickyHighlightIndex;

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
    final idx = _currentIndex;
    if (idx == null) return;
    _persistLyricIndex(idx);
    if (!PlaybackManager.instance.showLyric ||
        !_lyricsScrollController.hasClients) {
      return;
    }
    if (idx == _lastScrolledIndex) return;
    _lastScrolledIndex = idx;
    // Remember the cue we are now inside so the lyrics list keeps
    // its highlight during the gaps between cues, where
    // [_currentIndex] is null. Cleared when the user seeks or steps
    // out of any cue.
    _stickyHighlightIndex = idx;

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

  /// Writes the current lyric cue to [LastPlayedStore] so reopening the
  /// file jumps straight to the same line. The short-circuit on
  /// [_lastPersistedLyricIndex] debounces this to one disk write per
  /// cue change, so a long stretch of playback never writes more than
  /// once per lyric. Writes go through [_persistQueue] so consecutive
  /// writes are serialized — this guarantees the most recent cue is
  /// the one that ends up on disk.
  void _persistLyricIndex(int index) {
    if (index == _lastPersistedLyricIndex) return;
    _lastPersistedLyricIndex = index;
    final path = widget.videoFile?.path ?? widget.videoPath;
    final name = widget.videoName;
    if (path == null || path.isEmpty) return;
    _scheduleWrite(path, name, index);
  }

  void _scheduleWrite(String path, String name, int index) {
    final record = LastPlayed(path: path, name: name, lyricIndex: index);
    _persistQueue = _persistQueue
        .then((_) => LastPlayedStore.write(record))
        .catchError((_) {});
  }

  /// One-shot pre-pop hook: synchronously queue a write for the active
  /// cue (if any), then wait for it to land on disk before navigating
  /// away. Guarantees the home screen reads back the cue the user was
  /// actually on when they closed the player.
  Future<void> persistAndFlushBeforeClose() async {
    final idx = _currentIndex;
    if (idx != null) {
      final path = widget.videoFile?.path ?? widget.videoPath;
      final name = widget.videoName;
      if (path != null && path.isNotEmpty) {
        _scheduleWrite(path, name, idx);
      }
    }
    await _persistQueue;
  }

  void _seekToEntry(SubtitleEntry entry) {
    final pm = PlaybackManager.instance;
    final idx = _subtitles.indexOf(entry);
    final nextEntry = (idx >= 0 && idx + 1 < _subtitles.length)
        ? _subtitles[idx + 1]
        : null;
    pm.setLyricLoopSegment(start: entry.start, end: nextEntry?.start);
    pm.seek(entry.start);
    // Manual jumps (Home / End / ← / → / tapping a lyric line) land
    // outside the position-tick path, so persist the new index here
    // and snap the sticky highlight to it so the lyric list updates
    // immediately instead of waiting for the next position tick.
    if (idx >= 0) {
      _stickyHighlightIndex = idx;
      _lastScrolledIndex = idx;
      _persistLyricIndex(idx);
    }
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
            ? () => pm.setRepeatMode(LyricRepeatMode.repeatAll)
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
          backgroundColor: AppColors.videoBackdrop,
          body: Column(
            children: [
              CustomTitleBar(onClose: persistAndFlushBeforeClose),
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
                              bottom: 12,
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
                                onTap: () async {
                                  // Make sure the latest cue lands on
                                  // disk before we close the route, so
                                  // the home screen reads the right
                                  // lyricIndex when it refreshes.
                                  await persistAndFlushBeforeClose();
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                },
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
                          currentIndex: _stickyHighlightIndex ?? _currentIndex,
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
