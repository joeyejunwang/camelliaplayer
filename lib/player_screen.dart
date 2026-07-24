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

  @override
  void initState() {
    super.initState();
    final pm = PlaybackManager.instance;
    _videoController = VideoController(pm.player);

    pm.onPlayPreviousLyric = () => _seekToSubtitleIndex((_currentIndex ?? 0) - 1);
    pm.onPlayNextLyric = () => _seekToSubtitleIndex((_currentIndex ?? 0) + 1);
    pm.onPlayFirstLyric = () => _seekToSubtitleIndex(0);
    pm.onPlayLastLyric = () => _seekToSubtitleIndex(_subtitles.length - 1);

    _openMedia();
    _loadSubtitles();
    _positionSub = pm.player.stream.position.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
      _scrollToCurrent();
    });
  }

  Future<void> _openMedia() async {
    final pm = PlaybackManager.instance;
    final dir = p.dirname(Platform.resolvedExecutable);

    if (widget.videoFile != null) {
      final path = p.isAbsolute(widget.videoFile!.path)
          ? widget.videoFile!.path
          : p.join(dir, widget.videoFile!.path);
      pm.setMedia(Media(path), title: widget.videoName);
    } else if (widget.videoPath != null) {
      final path = p.isAbsolute(widget.videoPath!)
          ? widget.videoPath!
          : p.join(dir, widget.videoPath!);
      pm.setMedia(Media(path), title: widget.videoName);
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
    final nextEntry = (idx >= 0 && idx + 1 < _subtitles.length) ? _subtitles[idx + 1] : null;
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
        const SingleActivator(LogicalKeyboardKey.space): hasMedia ? () => pm.togglePlay() : noop,
        const SingleActivator(LogicalKeyboardKey.home): hasMedia ? () => pm.playFirstLyric() : noop,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): hasMedia ? () => pm.playPreviousLyric() : noop,
        const SingleActivator(LogicalKeyboardKey.arrowRight): hasMedia ? () => pm.playNextLyric() : noop,
        const SingleActivator(LogicalKeyboardKey.end): hasMedia ? () => pm.playLastLyric() : noop,
        const SingleActivator(LogicalKeyboardKey.keyR): hasMedia ? () => pm.toggleRepeatLyric() : noop,
        const SingleActivator(LogicalKeyboardKey.keyL): () => pm.toggleShowLyric(),
        const SingleActivator(LogicalKeyboardKey.arrowUp): hasMedia ? () => pm.setVolume((pm.volume + 0.1).clamp(0.0, 1.0)) : noop,
        const SingleActivator(LogicalKeyboardKey.arrowDown): hasMedia ? () => pm.setVolume((pm.volume - 0.1).clamp(0.0, 1.0)) : noop,
        const SingleActivator(LogicalKeyboardKey.keyS): hasMedia ? () => pm.toggleShowSubtitleTrack() : noop,
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
                          // Video
                          Positioned.fill(
                            child: Center(
                              child: Video(
                                controller: _videoController,
                                controls: NoVideoControls,
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
                                  child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
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
                                onTap: () => PlaybackManager.instance.toggleShowLyric(),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    PlaybackManager.instance.showLyric ? Icons.view_sidebar : Icons.view_sidebar_outlined,
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
          left: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
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
                  '${subtitles.length} lines',
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
