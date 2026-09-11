import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';

import 'subtitle_loader.dart';

/// iOS-specific video player screen using native video_player
class IOSPlayerScreen extends StatefulWidget {
  const IOSPlayerScreen({
    super.key,
    required this.videoPath,
    required this.videoName,
    this.subtitlePath,
  });

  final String videoPath;
  final String videoName;
  final String? subtitlePath;

  @override
  State<IOSPlayerScreen> createState() => _IOSPlayerScreenState();
}

class _IOSPlayerScreenState extends State<IOSPlayerScreen> {
  VideoPlayerController? _videoController;
  List<SubtitleEntry> _subtitles = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  bool _showLyrics = false;
  bool get _isMp3 {
    final ext = p.extension(widget.videoPath).toLowerCase();
    return ext == '.mp3' || ext == '.wav';
  }

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final file = File(widget.videoPath);
      _videoController = VideoPlayerController.file(file);
      await _videoController!.initialize();
      
      // Load subtitles if available
      if (widget.subtitlePath != null) {
        final subFile = File(widget.subtitlePath!);
        if (await subFile.exists()) {
          final loaded = await SubtitleLoader.loadFromFile(subFile);
          setState(() => _subtitles = loaded);
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
    setState(() {});
  }

  void _togglePlay() {
    if (_videoController == null) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  void _seekTo(Duration position) {
    _videoController?.seekTo(position);
  }

  /// Allows the user to manually pick a subtitle file at runtime. This is the
  /// main path on iOS because `FilePicker.platform.pickFiles` returns a temp
  /// path, so the basename-based lookup in the home screen cannot find an
  /// accompanying subtitle file.
  Future<void> _pickSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa', 'sub'],
      );
      if (result == null) return;
      final path = result.files.single.path;
      if (path == null) return;

      final file = File(path);
      if (!await file.exists()) return;
      final loaded = await SubtitleLoader.loadFromFile(file);
      if (!mounted) return;
      setState(() {
        _subtitles = loaded;
        _showLyrics = loaded.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load subtitle: $e');
    }
  }

  Duration get _position => _videoController?.value.position ?? Duration.zero;
  Duration get _duration => _videoController?.value.duration ?? Duration.zero;

  int? get _currentSubtitleIndex {
    for (int i = 0; i < _subtitles.length; i++) {
      if (_subtitles[i].textAt(_position) != null) return i;
    }
    return null;
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
          child: const Icon(
            CupertinoIcons.back,
            color: CupertinoColors.white,
          ),
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
            // Top control bar: subtitle picker + lyrics toggle (above player)
            if (!_isLoading && !_hasError)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _pickSubtitle,
                      child: const Icon(
                        CupertinoIcons.text_badge_plus,
                        color: CupertinoColors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(
                          () => _showLyrics = !_showLyrics),
                      child: Icon(
                        _showLyrics
                            ? CupertinoIcons.text_badge_checkmark
                            : CupertinoIcons.text_quote,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Video or Audio placeholder
                    if (_isMp3)
                      _AudioDisplay(
                        fileName: widget.videoName,
                        isPlaying: _videoController?.value.isPlaying ?? false,
                      )
                    else if (_isLoading)
                      const CupertinoActivityIndicator(color: CupertinoColors.white)
                    else if (_hasError)
                      _ErrorDisplay(message: _errorMessage ?? 'Unknown error')
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
                    
                    // Play/Pause overlay
                    if (!_isLoading && !_hasError && _showControls && !_isMp3)
                      AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: CupertinoColors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _videoController?.value.isPlaying ?? false
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_fill,
                            size: 48,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                    
                    // Subtitle overlay
                    if (!_isLoading && _subtitles.isNotEmpty)
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
            ),
            
            // Lyrics panel
            if (_showLyrics && _subtitles.isNotEmpty)
              _LyricsPanel(
                subtitles: _subtitles,
                currentIndex: _currentSubtitleIndex,
                onTap: (entry) {
                  _seekTo(entry.start);
                  setState(() => _showControls = true);
                },
              ),
            
            // Controls
            if (!_isLoading && !_hasError && !_isMp3)
              _VideoControls(
                position: _position,
                duration: _duration,
                isPlaying: _videoController?.value.isPlaying ?? false,
                onPlayPause: _togglePlay,
                onSeek: _seekTo,
                onSkipBack: () => _seekTo((_position - const Duration(seconds: 10)).clamp(Duration.zero, _duration)),
                onSkipForward: () => _seekTo((_position + const Duration(seconds: 10)).clamp(Duration.zero, _duration)),
                formatDuration: _formatDuration,
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
  const _AudioDisplay({
    required this.fileName,
    required this.isPlaying,
  });

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
  const _SubtitleOverlay({
    required this.subtitles,
    required this.currentIndex,
  });

  final List<SubtitleEntry> subtitles;
  final int? currentIndex;

  @override
  Widget build(BuildContext context) {
    if (currentIndex == null || currentIndex! < 0 || currentIndex! >= subtitles.length) {
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
    required this.onTap,
  });

  final List<SubtitleEntry> subtitles;
  final int? currentIndex;
  final void Function(SubtitleEntry) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
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
                  subtitles.isEmpty ? '' : '${currentIndex! + 1} / ${subtitles.length}',
                  style: TextStyle(
                    color: CupertinoColors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: subtitles.length,
              itemBuilder: (context, index) {
                final entry = subtitles[index];
                final isActive = index == currentIndex;
                
                return GestureDetector(
                  onTap: () => onTap(entry),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: isActive ? CupertinoColors.systemPink.withValues(alpha: 0.2) : null,
                    child: Text(
                      entry.text,
                      style: TextStyle(
                        color: isActive ? CupertinoColors.white : CupertinoColors.systemGrey,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
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

class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.formatDuration,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final void Function(Duration) onSeek;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final String Function(Duration) formatDuration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: CupertinoColors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar - use CupertinoSlider for iOS native look
          CupertinoSlider(
            value: duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                : 0.0,
            activeColor: CupertinoColors.systemPink,
            onChanged: (value) {
              final newPosition = Duration(
                milliseconds: (value * duration.inMilliseconds).round(),
              );
              onSeek(newPosition);
            },
          ),
          
          // Time and controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${formatDuration(position)} / ${formatDuration(duration)}',
                style: TextStyle(
                  color: CupertinoColors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onSkipBack,
                    child: const Icon(
                      CupertinoIcons.gobackward_10,
                      color: CupertinoColors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
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
                        isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                        color: CupertinoColors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onSkipForward,
                    child: const Icon(
                      CupertinoIcons.goforward_10,
                      color: CupertinoColors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 60), // Balance layout
            ],
          ),
        ],
      ),
    );
  }
}

extension on Duration {
  Duration clamp(Duration min, Duration max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }
}
