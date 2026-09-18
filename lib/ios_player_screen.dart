import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';

import 'last_played.dart';
import 'subtitle_loader.dart';

/// iOS-specific video player screen using native video_player
class IOSPlayerScreen extends StatefulWidget {
  const IOSPlayerScreen({
    super.key,
    required this.videoPath,
    required this.videoName,
    this.subtitlePath,
    this.initialLyricIndex,
  });

  final String videoPath;
  final String videoName;
  final String? subtitlePath;
  final int? initialLyricIndex;

  @override
  State<IOSPlayerScreen> createState() => _IOSPlayerScreenState();
}

class _IOSPlayerScreenState extends State<IOSPlayerScreen> {
  VideoPlayerController? _videoController;
  List<SubtitleEntry> _subtitles = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _showLyrics = true;
  bool _showSubtitleOverlay = true;
  bool _repeatLyric = true;
  bool _automaticSeekPending = false;
  int? _loopLyricIndex;
  int? _lastPersistedLyricIndex;
  Future<void> _persistQueue = Future<void>.value();
  int? _lastScrolledIndex;
  double _volume = 1;
  double _lastAudibleVolume = 1;
  final ScrollController _lyricsScrollController = ScrollController();
  bool get _isMp3 {
    final ext = p.extension(widget.videoPath).toLowerCase();
    return ext == '.mp3' || ext == '.wav' || ext == '.aac';
  }

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final file = File(widget.videoPath);
      _videoController = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
      );
      await _videoController!.initialize();

      // Load subtitles if available
      if (widget.subtitlePath != null) {
        final subFile = File(widget.subtitlePath!);
        if (await subFile.exists()) {
          final loaded = await SubtitleLoader.loadFromFile(subFile);
          if (!mounted) return;
          setState(() {
            _subtitles = loaded;
            _showLyrics = true;
          });
          if (loaded.isNotEmpty) {
            final initialIndex = _initialIndexFor(loaded);
            _loopLyricIndex = initialIndex;
            _persistLyricIndex(initialIndex);
            await _videoController!.seekTo(loaded[initialIndex].start);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = false;
      });

      _videoController!.play();
      _videoController!.addListener(_videoListener);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _videoListener() {
    if (!mounted || _videoController == null) return;
    _handleLyricPlayback();
    final index = _repeatLyric
        ? (_loopLyricIndex ?? _timelineLyricIndex)
        : _timelineLyricIndex;
    if (index >= 0) _persistLyricIndex(index);
    setState(() {});
    _scrollToCurrentLyric();
  }

  void _togglePlay() {
    if (_videoController == null) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  Future<void> _seekTo(Duration position) async {
    await _videoController?.seekTo(position);
  }

  /// Allows the user to manually pick a subtitle file at runtime. This is the
  /// main path on iOS because `FilePicker.platform.pickFiles` returns a temp
  /// path, so the basename-based lookup in the home screen cannot find an
  /// accompanying subtitle file.
  Future<void> _pickSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        // Custom extension filters can make SRT/ASS files unselectable in the
        // iOS document picker because those extensions may not have a UTType.
        type: FileType.any,
      );
      if (result == null) return;
      final path = result.files.single.path;
      if (path == null) return;

      const supportedExtensions = {'.srt', '.vtt', '.ass', '.ssa'};
      if (!supportedExtensions.contains(p.extension(path).toLowerCase())) {
        if (!mounted) return;
        _showSubtitleError('Choose an SRT, VTT, ASS, or SSA subtitle file.');
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        if (mounted) {
          _showSubtitleError('The selected subtitle is unavailable.');
        }
        return;
      }
      final loaded = await SubtitleLoader.loadFromFile(file);
      if (!mounted) return;
      if (loaded.isEmpty) {
        _showSubtitleError('No readable lyric cues were found in this file.');
        return;
      }
      setState(() {
        _subtitles = loaded;
        _showLyrics = loaded.isNotEmpty;
        _showSubtitleOverlay = true;
        _repeatLyric = true;
        _loopLyricIndex = _initialIndexFor(loaded);
      });
      final initialIndex = _loopLyricIndex!;
      _persistLyricIndex(initialIndex);
      await _videoController?.seekTo(loaded[initialIndex].start);
      await _videoController?.play();
    } catch (e) {
      if (!mounted) return;
      _showSubtitleError('Failed to load lyrics: $e');
    }
  }

  void _showSubtitleError(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Cannot load lyrics'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Duration get _position => _videoController?.value.position ?? Duration.zero;
  Duration get _duration => _videoController?.value.duration ?? Duration.zero;

  int? get _currentSubtitleIndex {
    for (int i = 0; i < _subtitles.length; i++) {
      if (_subtitles[i].textAt(_position) != null) return i;
    }
    return null;
  }

  int get _timelineLyricIndex {
    for (int i = _subtitles.length - 1; i >= 0; i--) {
      if (_position >= _subtitles[i].start) return i;
    }
    return -1;
  }

  int _initialIndexFor(List<SubtitleEntry> subtitles) {
    return (widget.initialLyricIndex ?? 0).clamp(0, subtitles.length - 1);
  }

  void _persistLyricIndex(int index) {
    if (index == _lastPersistedLyricIndex) return;
    _lastPersistedLyricIndex = index;
    final record = LastPlayed(
      path: widget.videoPath,
      name: widget.videoName,
      timestamp: DateTime.now(),
      lyricIndex: index,
    );
    _persistQueue = _persistQueue.then((_) => LastPlayedStore.write(record));
  }

  void _handleLyricPlayback() {
    final controller = _videoController;
    if (controller == null || _subtitles.isEmpty || _automaticSeekPending) {
      return;
    }

    final timelineIndex = _timelineLyricIndex;
    if (_repeatLyric) {
      final index = _loopLyricIndex ?? timelineIndex;
      if (index < 0 || index >= _subtitles.length) return;
      _loopLyricIndex = index;
      final entry = _subtitles[index];
      final end = index + 1 < _subtitles.length
          ? _subtitles[index + 1].start
          : entry.end;
      if (_position >= end || controller.value.isCompleted) {
        _automaticSeek(entry.start, resume: true);
      }
      return;
    }

    if (!controller.value.isPlaying || timelineIndex < 0) return;
    final current = _subtitles[timelineIndex];
    if (_position >= current.end) {
      final nextIndex = (timelineIndex + 1) % _subtitles.length;
      _automaticSeek(_subtitles[nextIndex].start, resume: true);
    }
  }

  void _automaticSeek(Duration position, {required bool resume}) {
    final controller = _videoController;
    if (controller == null) return;
    _automaticSeekPending = true;
    controller
        .seekTo(position)
        .then((_) {
          if (resume) return controller.play();
        })
        .whenComplete(() => _automaticSeekPending = false);
  }

  void _seekToSubtitleIndex(int index) {
    if (index < 0 || index >= _subtitles.length) return;
    _loopLyricIndex = index;
    _persistLyricIndex(index);
    unawaited(_seekTo(_subtitles[index].start));
  }

  void _stepLyric(int direction) {
    if (_subtitles.isEmpty) return;
    final active = _currentSubtitleIndex;
    int target;
    if (active != null) {
      target = (active + direction) % _subtitles.length;
    } else if (direction > 0) {
      target = _subtitles.indexWhere((entry) => entry.start > _position);
      if (target < 0) target = 0;
    } else {
      target = _subtitles.lastIndexWhere((entry) => entry.end < _position);
      if (target < 0) target = _subtitles.length - 1;
    }
    _seekToSubtitleIndex(target);
  }

  void _toggleRepeatLyric() {
    setState(() {
      _repeatLyric = !_repeatLyric;
      if (_repeatLyric) {
        final active = _currentSubtitleIndex;
        _loopLyricIndex =
            active ?? (_timelineLyricIndex >= 0 ? _timelineLyricIndex : 0);
      } else {
        _loopLyricIndex = null;
      }
    });
  }

  void _setVolume(double value) {
    final volume = value.clamp(0.0, 1.0);
    if (volume > 0) _lastAudibleVolume = volume;
    _videoController?.setVolume(volume);
    setState(() => _volume = volume);
  }

  void _toggleMute() {
    _setVolume(_volume == 0 ? _lastAudibleVolume : 0);
  }

  void _scrollToCurrentLyric() {
    if (!_showLyrics) return;
    final index = _currentSubtitleIndex;
    if (index == null || index == _lastScrolledIndex) return;
    _lastScrolledIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_lyricsScrollController.hasClients) return;
      const itemHeight = 52.0;
      final viewport = _lyricsScrollController.position.viewportDimension;
      final max = _lyricsScrollController.position.maxScrollExtent;
      final offset = index * itemHeight - viewport / 2 + itemHeight / 2;
      _lyricsScrollController.animateTo(
        offset.clamp(0.0, max),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black.withValues(alpha: 0.8),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, color: CupertinoColors.white),
        ),
        middle: Text(
          widget.videoName,
          style: const TextStyle(color: CupertinoColors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // iOS presentation of the same subtitle and lyric actions that
            // are available in the Windows player.
            if (!_isLoading && !_hasError)
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: CupertinoColors.black,
                  border: Border(
                    bottom: BorderSide(
                      color: CupertinoColors.systemGrey.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _IOSControlButton(
                      icon: CupertinoIcons.text_badge_plus,
                      onPressed: _pickSubtitle,
                    ),
                    _IOSControlButton(
                      icon: _repeatLyric
                          ? CupertinoIcons.repeat_1
                          : CupertinoIcons.repeat,
                      onPressed: _subtitles.isEmpty ? null : _toggleRepeatLyric,
                      isActive: _repeatLyric,
                    ),
                    _IOSControlButton(
                      icon: _showSubtitleOverlay
                          ? CupertinoIcons.captions_bubble_fill
                          : CupertinoIcons.captions_bubble,
                      onPressed: _subtitles.isEmpty
                          ? null
                          : () => setState(
                              () =>
                                  _showSubtitleOverlay = !_showSubtitleOverlay,
                            ),
                      isActive: _showSubtitleOverlay,
                    ),
                    _IOSControlButton(
                      icon: CupertinoIcons.text_quote,
                      onPressed: () =>
                          setState(() => _showLyrics = !_showLyrics),
                      isActive: _showLyrics,
                    ),
                    const Spacer(),
                    _IOSControlButton(
                      icon: _volume == 0
                          ? CupertinoIcons.volume_off
                          : CupertinoIcons.volume_up,
                      onPressed: _toggleMute,
                    ),
                    SizedBox(
                      width: 88,
                      child: CupertinoSlider(
                        value: _volume,
                        activeColor: CupertinoColors.systemPink,
                        onChanged: _setVolume,
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              flex: _showLyrics ? 4 : 9,
              fit: FlexFit.tight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Video or Audio placeholder
                  if (_isLoading)
                    const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  else if (_hasError)
                    _ErrorDisplay(message: _errorMessage ?? 'Unknown error')
                  else if (_isMp3)
                    _AudioDisplay(
                      fileName: widget.videoName,
                      isPlaying: _videoController?.value.isPlaying ?? false,
                    )
                  else
                    _buildVideoView(),

                  // Tap to play/pause
                  if (!_isLoading && !_hasError)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _togglePlay,
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox.expand(),
                      ),
                    ),

                  // Subtitle overlay
                  if (!_isLoading &&
                      _showSubtitleOverlay &&
                      _subtitles.isNotEmpty)
                    Positioned(
                      bottom: 60,
                      left: 20,
                      right: 20,
                      child: _SubtitleOverlay(
                        subtitles: _subtitles,
                        currentIndex: _currentSubtitleIndex,
                      ),
                    ),
                ],
              ),
            ),

            // Lyrics panel
            if (_showLyrics)
              Expanded(
                flex: 5,
                child: _LyricsPanel(
                  subtitles: _subtitles,
                  currentIndex: _currentSubtitleIndex,
                  position: _position,
                  duration: _duration,
                  formatDuration: _formatDuration,
                  scrollController: _lyricsScrollController,
                  onTap: (entry) {
                    _seekToSubtitleIndex(_subtitles.indexOf(entry));
                  },
                ),
              ),

            // Audio and video share the same playback feature set.
            if (!_isLoading && !_hasError)
              _IOSPlayerControls(
                isPlaying: _videoController?.value.isPlaying ?? false,
                subtitles: _subtitles,
                currentLyricIndex: _timelineLyricIndex,
                onPlayPause: _togglePlay,
                onFirstLyric: _subtitles.isEmpty
                    ? null
                    : () => _seekToSubtitleIndex(0),
                onPreviousLyric: _subtitles.isEmpty
                    ? null
                    : () => _stepLyric(-1),
                onNextLyric: _subtitles.isEmpty ? null : () => _stepLyric(1),
                onLastLyric: _subtitles.isEmpty
                    ? null
                    : () => _seekToSubtitleIndex(_subtitles.length - 1),
                onLyricChanged: _seekToSubtitleIndex,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoView() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      ),
    );
  }
}

class _AudioDisplay extends StatelessWidget {
  const _AudioDisplay({required this.fileName, required this.isPlaying});

  final String fileName;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: CupertinoColors.systemPink.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Icon(
            isPlaying ? CupertinoIcons.waveform : CupertinoIcons.music_note_2,
            size: 60,
            color: CupertinoColors.systemPink,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          fileName,
          style: const TextStyle(
            color: CupertinoColors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Audio Track',
          style: TextStyle(
            color: CupertinoColors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _ErrorDisplay extends StatelessWidget {
  const _ErrorDisplay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          size: 64,
          color: CupertinoColors.systemRed,
        ),
        const SizedBox(height: 16),
        const Text(
          'Failed to load video',
          style: TextStyle(
            color: CupertinoColors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(
            color: CupertinoColors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SubtitleOverlay extends StatelessWidget {
  const _SubtitleOverlay({required this.subtitles, required this.currentIndex});

  final List<SubtitleEntry> subtitles;
  final int? currentIndex;

  @override
  Widget build(BuildContext context) {
    if (currentIndex == null ||
        currentIndex! < 0 ||
        currentIndex! >= subtitles.length) {
      return const SizedBox.shrink();
    }

    final entry = subtitles[currentIndex!];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        entry.text,
        style: const TextStyle(
          color: CupertinoColors.white,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({
    required this.subtitles,
    required this.currentIndex,
    required this.position,
    required this.duration,
    required this.formatDuration,
    required this.scrollController,
    required this.onTap,
  });

  final List<SubtitleEntry> subtitles;
  final int? currentIndex;
  final Duration position;
  final Duration duration;
  final String Function(Duration) formatDuration;
  final ScrollController scrollController;
  final void Function(SubtitleEntry) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoColors.darkBackgroundGray,
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.text_quote,
                  size: 16,
                  color: CupertinoColors.systemGrey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Lyrics',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  subtitles.isEmpty || currentIndex == null
                      ? ''
                      : '${currentIndex! + 1} / ${subtitles.length}',
                  style: TextStyle(
                    color: CupertinoColors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    '${formatDuration(position)} / ${formatDuration(duration)}',
                    style: TextStyle(
                      color: CupertinoColors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: subtitles.isEmpty
                ? Center(
                    child: Text(
                      'No lyrics loaded',
                      style: TextStyle(
                        color: CupertinoColors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: subtitles.length,
                    itemExtent: 52,
                    itemBuilder: (context, index) {
                      final entry = subtitles[index];
                      final isActive = index == currentIndex;

                      return GestureDetector(
                        onTap: () => onTap(entry),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(
                                    0xFF5A1C2A,
                                  ).withValues(alpha: 0.95)
                                : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.text,
                            style: TextStyle(
                              color: isActive
                                  ? CupertinoColors.white
                                  : CupertinoColors.systemGrey,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _IOSPlayerControls extends StatelessWidget {
  const _IOSPlayerControls({
    required this.isPlaying,
    required this.subtitles,
    required this.currentLyricIndex,
    required this.onPlayPause,
    required this.onFirstLyric,
    required this.onPreviousLyric,
    required this.onNextLyric,
    required this.onLastLyric,
    required this.onLyricChanged,
  });

  final bool isPlaying;
  final List<SubtitleEntry> subtitles;
  final int currentLyricIndex;
  final VoidCallback onPlayPause;
  final VoidCallback? onFirstLyric;
  final VoidCallback? onPreviousLyric;
  final VoidCallback? onNextLyric;
  final VoidCallback? onLastLyric;
  final ValueChanged<int> onLyricChanged;

  @override
  Widget build(BuildContext context) {
    void selectLyric(double normalizedPosition) {
      final index = subtitles.length == 1
          ? 0
          : (normalizedPosition.clamp(0.0, 1.0) * (subtitles.length - 1))
                .round();
      onLyricChanged(index);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      color: CupertinoColors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitles.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Text(
                  'Lyrics',
                  style: TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const trackInset = 12.0;
                      final trackWidth = constraints.maxWidth - trackInset * 2;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final position = trackWidth <= 0
                              ? 0.0
                              : (details.localPosition.dx - trackInset) /
                                    trackWidth;
                          selectLyric(position);
                        },
                        child: CupertinoSlider(
                          value: subtitles.length == 1 || currentLyricIndex < 0
                              ? 0
                              : currentLyricIndex / (subtitles.length - 1),
                          activeColor: CupertinoColors.systemPink,
                          onChanged: selectLyric,
                        ),
                      );
                    },
                  ),
                ),
                Text(
                  currentLyricIndex < 0
                      ? '– / ${subtitles.length}'
                      : '${currentLyricIndex + 1} / ${subtitles.length}',
                  style: const TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _IOSControlButton(
                  icon: CupertinoIcons.backward_end_fill,
                  onPressed: onFirstLyric,
                ),
                _IOSControlButton(
                  icon: CupertinoIcons.backward_fill,
                  onPressed: onPreviousLyric,
                ),
                const SizedBox(width: 6),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onPlayPause,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: CupertinoColors.systemPink,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      color: CupertinoColors.white,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _IOSControlButton(
                  icon: CupertinoIcons.forward_fill,
                  onPressed: onNextLyric,
                ),
                _IOSControlButton(
                  icon: CupertinoIcons.forward_end_fill,
                  onPressed: onLastLyric,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IOSControlButton extends StatelessWidget {
  const _IOSControlButton({
    required this.icon,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      minimumSize: const Size(36, 36),
      onPressed: onPressed,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isActive
              ? CupertinoColors.systemPink.withValues(alpha: 0.24)
              : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 21,
          color: onPressed == null
              ? CupertinoColors.inactiveGray
              : isActive
              ? CupertinoColors.systemPink
              : CupertinoColors.white,
        ),
      ),
    );
  }
}
