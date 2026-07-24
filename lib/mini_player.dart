import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'playback_manager.dart';
class _CircleProgress extends StatelessWidget {
  const _CircleProgress({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    this.strokeWidth = 3,
    this.size = 40,
  });

  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CircleProgressPainter(
          progress: progress.clamp(0.0, 1.0),
          color: color,
          backgroundColor: backgroundColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _CircleProgressPainter extends CustomPainter {
  _CircleProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (math.min(cx, cy) - strokeWidth / 2);

    final bg = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), radius, bg);

    if (progress <= 0) return;

    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(_CircleProgressPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.backgroundColor != backgroundColor;
}

/// Compact horizontal volume slider (0–100).
class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({required this.volume, required this.onChanged});

  final double volume; // 0.0 – 1.0
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            volume == 0
                ? Icons.volume_off
                : volume < 0.4
                    ? Icons.volume_mute
                    : volume < 0.75
                        ? Icons.volume_down
                        : Icons.volume_up,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 54,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
                thumbColor: theme.colorScheme.primary,
                overlayColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: volume,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Voice recorder widget ─────────────────────────────────────────────────────

class _VoiceRecorder extends StatefulWidget {
  const _VoiceRecorder();

  @override
  State<_VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<_VoiceRecorder> with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Amplitude _amplitude = Amplitude(current: -160.0, max: -160.0);
  Timer? _amplitudeTimer;
  DateTime? _startTime;

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _amplitudeTimer?.cancel();
      await _recorder.stop();
      setState(() => _isRecording = false);
    } else {
      if (!await _recorder.hasPermission()) return;
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, bitRate: 128000),
        path: '${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      setState(() {
        _isRecording = true;
        _startTime = DateTime.now();
      });
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
        if (!mounted || !_isRecording) return;
        final amp = await _recorder.getAmplitude();
        if (mounted) setState(() => _amplitude = amp);
      });
    }
  }

  String get _elapsed {
    if (_startTime == null) return '00:00';
    final diff = DateTime.now().difference(_startTime!);
    return '${diff.inMinutes.remainder(60).toString().padLeft(2, '0')}:${diff.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final norm = ((_amplitude.current + 60) / 60).clamp(0.0, 1.0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV): _toggleRecording,
      },
      child: Focus(
        autofocus: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRecording)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: 'Voice recorder (V)',
                  child: Text(
                    _elapsed,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            if (_isRecording)
              Container(
                width: 48,
                height: 28,
                margin: const EdgeInsets.only(right: 4),
                child: CustomPaint(
                  painter: _WaveformPainter(amplitude: norm, color: theme.colorScheme.error),
                  size: const Size(48, 28),
                ),
              ),
            GestureDetector(
              onTap: _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? theme.colorScheme.error
                      : theme.colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: _isRecording
                        ? theme.colorScheme.error
                        : theme.colorScheme.outlineVariant,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isRecording
                        ? Icon(Icons.stop_rounded, key: const ValueKey('stop'), size: 16, color: theme.colorScheme.onError)
                        : Icon(Icons.mic_rounded, key: const ValueKey('mic'), size: 16, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.amplitude, required this.color});
  final double amplitude;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 5;
    final barW = size.width / (barCount * 2 - 1);
    final maxH = size.height;
    final rng = math.Random(42); // fixed seed for stable shape

    for (var i = 0; i < barCount; i++) {
      final phase = i / barCount;
      final h = maxH * (0.2 + amplitude * (0.5 + 0.5 * math.sin(phase * math.pi)) * (0.6 + 0.4 * rng.nextDouble()));
      final x = i * (barW * 2);
      final y = (maxH - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barW, h), Radius.circular(barW / 2)),
        Paint()..color = color.withValues(alpha: 0.4 + 0.6 * amplitude),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.amplitude != amplitude;
}

// (Keyboard shortcuts are now declared in player_screen.dart using
// CallbackShortcuts so that all global keys are handled where the page's
// primary Focus node lives.)

// ─── Consistent mini-player button ────────────────────────────────────────────

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget btn = Material(
      color: isActive
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color: isActive ? theme.colorScheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// Bottom mini-player bar replacing the NavigationBar.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  static const double height = 80;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pm = PlaybackManager.instance;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const Border(
        top: BorderSide(color: Colors.transparent, width: 0.5),
      ),
      child: SizedBox(
        height: height,
        child: ListenableBuilder(
          listenable: pm,
          builder: (context, _) {
            final hasMedia = pm.hasMedia;
            final isPlaying = pm.isPlaying;
            final progress = pm.progress;
            final vol = pm.volume;
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                // ── Progress ring ───────────────────────────────────────────
                const SizedBox(width: 20),

                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (hasMedia)
                        _CircleProgress(
                          progress: progress,
                          color: theme.colorScheme.primary,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          strokeWidth: 3,
                          size: 44,
                        )
                      else
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      GestureDetector(
                        onTap: hasMedia ? () => pm.togglePlay() : null,
                        child: Icon(
                          hasMedia
                              ? (isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded)
                              : Icons.music_note_outlined,
                          color: hasMedia
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // ── Transport controls: skip-back / rewind / fast-forward / skip-next ──
                if (hasMedia)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MiniBtn(
                        icon: Icons.skip_previous_rounded,
                        onPressed: () => pm.playFirstLyric(),
                        tooltip: 'First lyric',
                      ),
                      const SizedBox(width: 4),
                      _MiniBtn(
                        icon: Icons.fast_rewind_rounded,
                        onPressed: () => pm.playPreviousLyric(),
                        tooltip: 'Previous lyric',
                      ),
                      const SizedBox(width: 4),
                      _MiniBtn(
                        icon: Icons.fast_forward_rounded,
                        onPressed: () => pm.playNextLyric(),
                        tooltip: 'Next lyric',
                      ),
                      const SizedBox(width: 4),
                      _MiniBtn(
                        icon: Icons.skip_next_rounded,
                        onPressed: () => pm.playLastLyric(),
                        tooltip: 'Last lyric',
                      ),
                      const SizedBox(width: 4),
                    ],
                  )
                else
                  const SizedBox(width: 152),

                // ── Repeat switch (loops current lyric if one is active; otherwise whole track) ──
                _MiniBtn(
                  icon: pm.repeatLyric
                      ? Icons.repeat_on_rounded
                      : Icons.repeat_rounded,
                  onPressed: hasMedia ? () => pm.toggleRepeatLyric() : null,
                  tooltip: pm.repeatLyric
                      ? 'Repeat on — click to turn off'
                      : 'Repeat off — click to loop current lyric',
                  isActive: pm.repeatLyric,
                ),
                const SizedBox(width: 4),

                // ── Subtitle track toggle ──
                _MiniBtn(
                  icon: pm.showSubtitleTrack
                      ? Icons.closed_caption_rounded
                      : Icons.closed_caption_off_rounded,
                  onPressed: hasMedia ? () => pm.toggleShowSubtitleTrack() : null,
                  tooltip: pm.showSubtitleTrack
                      ? 'Subtitles on — click to turn off'
                      : 'Subtitles off — click to enable',
                  isActive: pm.showSubtitleTrack,
                ),
                const SizedBox(width: 4),

                // ── Lyric visibility toggle ──
                _MiniBtn(
                  icon: pm.showLyric
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  onPressed: hasMedia ? () => pm.toggleShowLyric() : null,
                  tooltip: pm.showLyric
                      ? 'Show lyric on — click to turn off'
                      : 'Show lyric off — click to show current lyric',
                  isActive: pm.showLyric,
                ),

                // ── Spacer to push recorder to far right ──────────────────
                const Spacer(),

                // ── Volume slider ────────────────────────────────────────────
                if (hasMedia)
                  SizedBox(
                    width: 100,
                    child: _VolumeSlider(
                      volume: vol,
                      onChanged: (v) => pm.setVolume(v),
                    ),
                  )
                else
                  const SizedBox(width: 100),
              ],
            ),
          );
          },
        ),
      ),
    );
  }
}
