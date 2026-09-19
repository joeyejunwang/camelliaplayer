import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'last_played.dart';
import 'player_screen.dart';

const _mediaExts = [
  'mp3', 'aac', 'wav',
  'mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi', 'wmv',
];
const _subtitleExts = ['srt', 'vtt', 'ass', 'ssa'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _videoPath;
  LastPlayed? _lastPlayed;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _refreshLast();
  }

  Future<void> _refreshLast() async {
    final lp = await LastPlayedStore.read();
    if (!mounted) return;
    if (lp != null && !File(lp.path).existsSync()) {
      await LastPlayedStore.clear();
      setState(() => _lastPlayed = null);
      return;
    }
    setState(() => _lastPlayed = lp);
  }

  Future<void> _openMedia(String path, {int? initialLyricIndex}) async {
    final file = File(path);
    if (!file.existsSync()) {
      _toast('File not found: $path');
      return;
    }
    final name = file.path.split(Platform.pathSeparator).last;
    final base = file.path.replaceAll(RegExp(r'\.[^.]+$'), '');
    File? subtitle;
    for (final e in _subtitleExts) {
      final f = File('$base.$e');
      if (f.existsSync()) {
        subtitle = f;
        break;
      }
    }
    // Fallback: look in the same folder for any subtitle file whose
    // name shares a prefix with the video (e.g. "song.mp3" matches
    // "song.pt.srt"). Lets the player jump straight to the first lyric
    // even when the lyric file isn't named identically to the video.
    subtitle ??= _closestSubtitleIn(file.parent.path, base);
    await LastPlayedStore.write(
      LastPlayed(path: path, name: name),
    );
    if (!mounted) return;
    setState(() => _videoPath = name);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoFile: file,
          videoPath: name,
          videoName: name,
          subtitleFile: subtitle,
          subtitlePath: subtitle?.path.split(Platform.pathSeparator).last,
          initialLyricIndex: initialLyricIndex,
        ),
      ),
    );
    if (mounted) await _refreshLast();
  }

  Future<void> _pick() async {
    final f = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Audio and video', extensions: _mediaExts),
      ],
    );
    if (f != null && mounted) await _openMedia(f.path);
  }

  Future<void> _onDrop(List<XFile> xfiles) async {
    final pick = xfiles.firstWhere(
      (x) => _mediaExts.contains(
        x.name.contains('.') ? x.name.split('.').last.toLowerCase() : '',
      ),
      orElse: () => XFile(''),
    );
    if (pick.path.isEmpty) {
      _toast('No supported media file in the drop.');
      return;
    }
    await _openMedia(pick.path);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  /// Find the subtitle file in [dir] whose name shares the longest
  /// prefix with [base]. Returns the best match or null if [dir] has no
  /// subtitle files. Used to fall back when there is no `<video>.<ext>`
  /// sibling, so the player can still jump to the first lyric on open.
  File? _closestSubtitleIn(String dir, String base) {
    final directory = Directory(dir);
    if (!directory.existsSync()) return null;
    File? best;
    int bestScore = -1;
    final baseStem = base
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .toLowerCase();
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path
          .split(Platform.pathSeparator)
          .last
          .toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      final ext = name.substring(dot + 1);
      if (!_subtitleExts.contains(ext)) continue;
      final stem = name.substring(0, dot);
      var score = 0;
      final max = stem.length < baseStem.length ? stem.length : baseStem.length;
      for (var i = 0; i < max; i++) {
        if (stem[i] != baseStem[i]) break;
        score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = entity;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF120A10), // deep camellia shadow
              AppColors.panelDark,
              Color(0xFF2A1419), // subtle warm wash toward the bottom
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) async {
            setState(() => _dragging = false);
            await _onDrop(d.files);
          },
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(theme: t),
                      const SizedBox(height: 36),
                      _Card(
                        onTap: _pick,
                        child: Row(
                          children: [
                            _IconBadge(
                              icon: _videoPath == null
                                  ? Icons.folder_open_rounded
                                  : Icons.movie_rounded,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _videoPath ?? 'Choose a media file',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Audio & video (.mp4, .mp3, .aac, .wav, …)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _pick,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Browse'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_lastPlayed != null) ...[
                        _LastPlayed(
                          record: _lastPlayed!,
                          onPlay: () => _openMedia(
                            _lastPlayed!.path,
                            initialLyricIndex: _lastPlayed!.lyricIndex,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _Card(
                        child: Row(
                          children: [
                            _IconBadge(
                              icon: Icons.swipe_down_alt_rounded,
                              tint: cs.tertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '…or drag & drop a file anywhere',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_dragging) const _DropOverlay(),
          ],
        ),
      ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/branding/camellia_player_icon_1024.png',
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Camellia Player',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'A simple audio & video player',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, this.tint});
  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = tint ?? cs.primary;
    return Container(
      height: 36,
      width: 36,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: c),
    );
  }
}

class _LastPlayed extends StatelessWidget {
  const _LastPlayed({required this.record, required this.onPlay});
  final LastPlayed record;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return _Card(
      child: Row(
        children: [
          _IconBadge(
            icon: Icons.history_rounded,
            tint: cs.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LAST PLAYED',
                  style: t.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  record.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            style: IconButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.primary, width: 2.5),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_download_rounded,
                  size: 56, color: cs.onPrimaryContainer),
              const SizedBox(height: 14),
              Text(
                'Drop to play',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
