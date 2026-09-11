import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'last_played.dart';
import 'player_screen.dart';

/// Extensions accepted for drag-and-drop / file picker.
const _supportedExts = [
  'mp3', 'wav', 'mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi', 'wmv',
];

/// Subtitle candidates looked up next to the media file (basename + ext).
const _subtitleExts = ['srt', 'vtt', 'ass', 'ssa', 'sub'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _videoPath;
  LastPlayed? _lastPlayed;
  bool _isDragHovering = false;

  @override
  void initState() {
    super.initState();
    _refreshLastPlayed();
  }

  Future<void> _refreshLastPlayed() async {
    final lp = await LastPlayedStore.read();
    if (!mounted) return;
    // Hide entries whose backing file no longer exists on disk.
    if (lp != null && !File(lp.path).existsSync()) {
      await LastPlayedStore.clear();
      setState(() => _lastPlayed = null);
      return;
    }
    setState(() => _lastPlayed = lp);
  }

  /// Open a media file: locate a sibling subtitle (if any), record it as
  /// last-played, then navigate to [PlayerScreen].
  Future<void> _openMediaFile(String absolutePath) async {
    final file = File(absolutePath);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File not found: $absolutePath')),
      );
      return;
    }

    final displayName = file.path.split(Platform.pathSeparator).last;
    final baseName = file.path.replaceAll(RegExp(r'\.[^.]+$'), '');

    File? foundSubtitle;
    for (final ext in _subtitleExts) {
      final subPath = '$baseName.$ext';
      final subFile = File(subPath);
      if (subFile.existsSync()) {
        foundSubtitle = subFile;
        break;
      }
    }

    await LastPlayedStore.write(
      LastPlayed(path: absolutePath, name: displayName, timestamp: DateTime.now()),
    );

    setState(() => _videoPath = displayName);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoFile: file,
          videoPath: displayName,
          videoName: displayName,
          subtitleFile: foundSubtitle,
          subtitlePath: foundSubtitle?.path.split(Platform.pathSeparator).last,
        ),
      ),
    );
    // Refresh last-played when the user returns so deletions / changes
    // are reflected back on the home screen.
    if (mounted) await _refreshLastPlayed();
  }

  Future<void> _pickVideo() async {
    const typeGroup = XTypeGroup(
      label: 'Audio and video',
      extensions: _supportedExts,
    );
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;
    await _openMediaFile(file.path);
  }

  /// Called by [DropTarget] when files are dropped onto the home screen.
  Future<void> _handleDropped(List<XFile> xfiles) async {
    if (xfiles.isEmpty) return;
    // Pick the first file with a supported extension.
    XFile? chosen;
    for (final xf in xfiles) {
      final ext = xf.name.contains('.')
          ? xf.name.split('.').last.toLowerCase()
          : '';
      if (_supportedExts.contains(ext)) {
        chosen = xf;
        break;
      }
    }
    if (chosen == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No supported media file in the drop. Try .mp4 or .wav.'),
        ),
      );
      return;
    }
    await _openMediaFile(chosen.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: DropTarget(
          onDragEntered: (_) => setState(() => _isDragHovering = true),
          onDragExited: (_) => setState(() => _isDragHovering = false),
          onDragDone: (details) async {
            setState(() => _isDragHovering = false);
            await _handleDropped(details.files);
          },
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    _Header(theme: theme),
                    const SizedBox(height: 32),
                    _PickerCard(
                      title: 'Audio or video file',
                      subtitle: _videoPath ?? 'Pick or drop an .mp4, .wav, .mp3, …',
                      icon: Icons.perm_media_outlined,
                      actionLabel: 'Choose file',
                      onTap: _pickVideo,
                    ),
                    const SizedBox(height: 16),
                    _DropHint(theme: theme, active: _isDragHovering),
                    if (_lastPlayed != null) ...[
                      const SizedBox(height: 16),
                      _LastPlayedCard(
                        theme: theme,
                        record: _lastPlayed!,
                        onReplay: () => _openMediaFile(_lastPlayed!.path),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _TipBanner(theme: theme),
                  ],
                ),
              ),
              if (_isDragHovering) _DropOverlay(theme: theme),
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
    return Row(
      children: [
        Container(
          height: 56,
          width: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.play_circle_fill_rounded,
            size: 36,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Camellia Player',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A simple Flutter audio and video player for Windows & Web.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint({required this.theme, required this.active});
  final ThemeData theme;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = active
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final bg = active
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerLow;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.file_download_rounded, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '…or drag & drop a media file anywhere on this window',
              style: theme.textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.primary, width: 2),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.file_download_rounded,
                size: 64,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(height: 12),
              Text(
                'Drop to play',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
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

class _LastPlayedCard extends StatelessWidget {
  const _LastPlayedCard({
    required this.theme,
    required this.record,
    required this.onReplay,
  });

  final ThemeData theme;
  final LastPlayed record;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onReplay,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primary,
                child: Icon(
                  Icons.replay_rounded,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last played',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onReplay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Replay'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipBanner extends StatelessWidget {
  const _TipBanner({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tip: drag the window edges to resize, or press F11 in browser fullscreen for the best playback experience.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  icon,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: onTap, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
