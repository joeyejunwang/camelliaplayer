import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _videoFile;
  File? _subtitleFile;
  String? _videoPath;
  String? _subtitlePath;

  Future<void> _pickVideo() async {
    const typeGroup = XTypeGroup(
      label: 'video',
      extensions: ['mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi', 'wmv'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    setState(() {
      _videoPath = file.name;
      _videoFile = File(file.path);
    });
  }

  Future<void> _pickSubtitle() async {
    const typeGroup = XTypeGroup(
      label: 'subtitles',
      extensions: ['srt', 'vtt', 'ass', 'ssa', 'sub'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    setState(() {
      _subtitlePath = file.name;
      _subtitleFile = File(file.path);
    });
  }

  void _openPlayer() {
    if (_videoFile == null && _videoPath == null) {
      _showSnack('Pick a video file first.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoFile: _videoFile,
          videoPath: _videoPath,
          videoName: _videoPath ?? 'video',
          subtitleFile: _subtitleFile,
          subtitlePath: _subtitlePath,
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasVideo = _videoFile != null || _videoPath != null;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Row(
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
                              'A simple Flutter video player for Windows & Web.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _PickerCard(
                    title: 'Video file',
                    subtitle: _videoPath ?? 'Pick an .mp4, .mkv, .webm, …',
                    icon: Icons.movie_outlined,
                    actionLabel: 'Choose video',
                    onTap: _pickVideo,
                  ),
                  const SizedBox(height: 16),
                  _PickerCard(
                    title: 'Subtitle file (optional)',
                    subtitle: _subtitlePath ?? 'Pick a .srt, .vtt, .ass file',
                    icon: Icons.subtitles_outlined,
                    actionLabel: 'Choose subtitle',
                    onTap: _pickSubtitle,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: hasVideo ? _openPlayer : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Open player',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
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
                  ),
                ],
              ),
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
