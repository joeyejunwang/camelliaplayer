import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'ise_rating_service.dart';
import 'media_library_store.dart';
import 'playback_manager.dart';

/// Live microphone feedback shown over the video during Talking mode.
class TalkingVoiceWave extends StatefulWidget {
  const TalkingVoiceWave({super.key});

  @override
  State<TalkingVoiceWave> createState() => _TalkingVoiceWaveState();
}

class _TalkingVoiceWaveState extends State<TalkingVoiceWave> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _amplitudeTimer;
  String? _temporaryPath;
  List<double> _samples = List<double>.filled(32, 0.03);
  bool _recording = false;
  bool _transitioning = false;
  bool _speakingTurn = false;

  @override
  void initState() {
    super.initState();
    final manager = PlaybackManager.instance;
    _speakingTurn =
        manager.playerMode == PlayerMode.talking &&
        manager.isTalkingRecording &&
        manager.hasMedia;
    manager.addListener(_syncRecordingState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRecordingState());
  }

  @override
  void dispose() {
    PlaybackManager.instance.removeListener(_syncRecordingState);
    _amplitudeTimer?.cancel();
    unawaited(_disposeRecorder());
    super.dispose();
  }

  Future<void> _disposeRecorder() async {
    if (_recording) {
      try {
        final savedPath = await _recorder.stop();
        if (savedPath != null) {
          _handleSavedRecording(savedPath);
        }
      } catch (_) {}
    }
    await _recorder.dispose();
  }

  void _syncRecordingState() {
    final manager = PlaybackManager.instance;
    final shouldRecord =
        manager.playerMode == PlayerMode.talking &&
        manager.isTalkingRecording &&
        manager.hasMedia;
    if (_speakingTurn != shouldRecord) {
      _speakingTurn = shouldRecord;
      if (mounted) setState(() {});
    }
    if (shouldRecord && !_recording && !_transitioning) {
      unawaited(_startRecording());
    } else if (!shouldRecord && _recording && !_transitioning) {
      unawaited(_stopRecording());
    }
  }

  Future<void> _startRecording() async {
    _transitioning = true;
    IseRatingService.clearRating();
    try {
      if (!await _recorder.hasPermission()) return;
      final settings = await MediaLibraryStore.read();
      final device = await _resolveDevice(settings.recordingDeviceId);
      final temp = await getTemporaryDirectory();
      _temporaryPath = p.join(
        temp.path,
        'camellia_talking_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
          device: device,
        ),
        path: _temporaryPath!,
      );
      _recording = true;
      _samples = List<double>.filled(32, 0.03);
      _amplitudeTimer = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => unawaited(_sampleAmplitude()),
      );
    } catch (_) {
      _recording = false;
    } finally {
      _transitioning = false;
      if (mounted) setState(() {});
    }
  }

  Future<InputDevice?> _resolveDevice(String savedId) async {
    if (savedId.isEmpty) return null;
    try {
      final devices = await _recorder.listInputDevices();
      for (final device in devices) {
        if (device.id == savedId) return device;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _sampleAmplitude() async {
    if (!_recording) return;
    try {
      final value = await _recorder.getAmplitude();
      final normalized = value.current.isFinite
          ? ((value.current + 60) / 60).clamp(0.0, 1.0).toDouble()
          : 0.0;
      if (mounted) {
        setState(() {
          _samples = [..._samples.skip(1), normalized];
        });
      }
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    _transitioning = true;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    try {
      final savedPath = await _recorder.stop();
      if (savedPath != null) {
        _handleSavedRecording(savedPath);
      }
    } catch (_) {}
    _recording = false;
    _samples = List<double>.filled(32, 0.03);
    _transitioning = false;
    if (mounted) setState(() {});
  }

  void _handleSavedRecording(String savedPath) {
    _temporaryPath = savedPath;
    debugPrint('Talking recording saved to $savedPath');
    final reference = PlaybackManager.instance.talkingReferenceText;
    if (reference == null || reference.trim().isEmpty) return;
    unawaited(
      IseRatingService.rateAndSave(wavPath: savedPath, reference: reference),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_speakingTurn) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = _speakingTurn ? theme.colorScheme.primary : Colors.white54;
    final background = dark
        ? Colors.black.withValues(alpha: _speakingTurn ? 0.72 : 0.48)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.96);
    return MouseRegion(
      cursor: _speakingTurn
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: PlaybackManager.instance.stopTalkingRecording,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 340,
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _speakingTurn
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.22),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                _speakingTurn ? Icons.mic_rounded : Icons.hearing_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: CustomPaint(
                    painter: _TalkingWavePainter(
                      samples: _speakingTurn ? _samples : const <double>[],
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _speakingTurn ? 'Your turn' : 'Listen',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TalkingWavePainter extends CustomPainter {
  const _TalkingWavePainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final bars = samples.isEmpty ? 24 : samples.length;
    final spacing = size.width / bars;
    for (var index = 0; index < bars; index++) {
      final level = samples.isEmpty ? 0.04 : samples[index];
      final height = (size.height * level).clamp(3.0, size.height).toDouble();
      final x = spacing * index + spacing / 2;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TalkingWavePainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.color != color;
}
