import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ios_player_screen.dart';
import 'last_played.dart';

/// Supported media extensions for iOS
const _supportedExts = [
  'mp3',
  'wav',
  'aac',
  'mp4',
  'm4v',
  'mkv',
  'webm',
  'mov',
  'avi',
];

/// Subtitle candidates looked up next to the media file (basename + ext).
const _subtitleExts = ['srt', 'vtt', 'ass', 'ssa'];

/// iOS-specific home screen that displays a list of MP4/media files.
class IOSHomeScreen extends StatefulWidget {
  const IOSHomeScreen({super.key});

  @override
  State<IOSHomeScreen> createState() => _IOSHomeScreenState();
}

class _IOSHomeScreenState extends State<IOSHomeScreen> {
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;
  String? _currentDirectory;
  final List<String> _directoryStack = [];
  LastPlayed? _lastPlayed;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _loadLastPlayed();
  }

  Future<void> _loadLastPlayed() async {
    final lp = await LastPlayedStore.read();
    if (!mounted) return;
    if (lp != null && !await File(lp.path).exists()) {
      await LastPlayedStore.clear();
      if (!mounted) return;
      setState(() => _lastPlayed = null);
      return;
    }
    setState(() => _lastPlayed = lp);
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);

    try {
      List<FileSystemEntity> entities;

      if (_currentDirectory == null) {
        // Load from documents directory
        final docDir = await getApplicationDocumentsDirectory();
        _currentDirectory = docDir.path;
        entities = await _listMediaFiles(docDir.path);
      } else {
        entities = await _listMediaFiles(_currentDirectory!);
      }

      if (!mounted) return;
      setState(() {
        _files = entities;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _files = [];
        _isLoading = false;
      });
    }
  }

  Future<List<FileSystemEntity>> _listMediaFiles(String directoryPath) async {
    try {
      final dir = Directory(directoryPath);
      if (!await dir.exists()) return [];

      final entities = await dir.list().toList();
      final mediaFiles = <FileSystemEntity>[];

      for (final entity in entities) {
        if (entity is File) {
          final ext = p
              .extension(entity.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (_supportedExts.contains(ext)) {
            mediaFiles.add(entity);
          }
        } else if (entity is Directory) {
          // Add directories (except hidden ones)
          final name = p.basename(entity.path);
          if (!name.startsWith('.')) {
            mediaFiles.add(entity);
          }
        }
      }

      // Sort: directories first, then files, alphabetically
      mediaFiles.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });

      return mediaFiles;
    } catch (e) {
      return [];
    }
  }

  Future<void> _openFile(
    String path, {
    String? selectedSubtitlePath,
    int? initialLyricIndex,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      if (!mounted) return;
      _showError('File not found: $path');
      return;
    }

    final displayName = p.basename(path);
    final mediaBaseName = p.basenameWithoutExtension(path).toLowerCase();

    // A Files-picker selection is passed explicitly because iOS can copy each
    // selected document into a separate temporary location. Files opened from
    // the app's Documents browser can be matched by enumerating their folder.
    File? foundSubtitle = selectedSubtitlePath == null
        ? null
        : File(selectedSubtitlePath);
    if (foundSubtitle != null && !await foundSubtitle.exists()) {
      foundSubtitle = null;
    }
    if (foundSubtitle == null) {
      try {
        await for (final entity in File(path).parent.list()) {
          if (entity is! File) continue;
          final extension = p
              .extension(entity.path)
              .toLowerCase()
              .replaceFirst('.', '');
          final candidateBase = p
              .basenameWithoutExtension(entity.path)
              .toLowerCase();
          if (_subtitleExts.contains(extension) &&
              candidateBase == mediaBaseName) {
            foundSubtitle = entity;
            break;
          }
        }
      } catch (_) {
        // External Files locations may only grant access to selected documents.
      }
    }

    // Save as last played
    await LastPlayedStore.write(
      LastPlayed(
        path: path,
        name: displayName,
        lyricIndex: initialLyricIndex,
      ),
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => IOSPlayerScreen(
          videoPath: path,
          videoName: displayName,
          subtitlePath: foundSubtitle?.path,
          initialLyricIndex: initialLyricIndex,
        ),
      ),
    );
    _loadLastPlayed();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      // iOS does not consistently register subtitle extensions such as SRT
      // as UTTypes. Using FileType.custom can therefore grey them out.
      // Show all documents and validate the selected extensions below.
      type: FileType.any,
      allowMultiple: true,
    );

    if (result == null) return;
    final pickedPaths = result.files
        .map((file) => file.path)
        .whereType<String>()
        .toList();
    if (pickedPaths.length > 2) {
      if (mounted) {
        _showError(
          'Select no more than two files: one media file and one lyric file.',
        );
      }
      return;
    }

    final mediaPaths = pickedPaths.where((path) {
      final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
      return _supportedExts.contains(extension);
    }).toList();
    final subtitlePaths = pickedPaths.where((path) {
      final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
      return _subtitleExts.contains(extension);
    }).toList();

    if (mediaPaths.length != 1) {
      if (mounted) {
        _showError('Select exactly one audio or video file.');
      }
      return;
    }

    final mediaPath = mediaPaths.single;
    final mediaBase = p.basenameWithoutExtension(mediaPath).toLowerCase();
    final subtitlePath = subtitlePaths.isEmpty ? null : subtitlePaths.single;
    if (subtitlePath != null &&
        p.basenameWithoutExtension(subtitlePath).toLowerCase() != mediaBase) {
      if (mounted) {
        _showError(
          'The media and lyric files must have the same name, such as video.mp4 and video.srt.',
        );
      }
      return;
    }
    if (pickedPaths.length == 2 && subtitlePath == null) {
      if (mounted) {
        _showError(
          'The second file must be an SRT, VTT, ASS, or SSA lyric file.',
        );
      }
      return;
    }

    await _openFile(mediaPath, selectedSubtitlePath: subtitlePath);
  }

  void _navigateToDirectory(String path) {
    setState(() {
      _directoryStack.add(_currentDirectory!);
      _currentDirectory = path;
    });
    _loadFiles();
  }

  void _navigateBack() {
    if (_directoryStack.isNotEmpty) {
      setState(() {
        _currentDirectory = _directoryStack.removeLast();
      });
      _loadFiles();
    }
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          _currentDirectory != null
              ? p.basename(_currentDirectory!)
              : 'Camellia Player',
        ),
        leading: _directoryStack.isNotEmpty
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _navigateBack,
                child: const Icon(CupertinoIcons.back),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _loadFiles,
              child: const Icon(CupertinoIcons.refresh),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _pickFile,
              child: const Icon(CupertinoIcons.folder_open),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Last played card
            if (_lastPlayed != null)
              _LastPlayedCard(
                record: _lastPlayed!,
                onTap: () => _openFile(
                  _lastPlayed!.path,
                  initialLyricIndex: _lastPlayed!.lyricIndex,
                ),
              ),

            // File list
            Expanded(
              child: _isLoading
                  ? const Center(child: CupertinoActivityIndicator())
                  : _files.isEmpty
                  ? _EmptyState(onPickFile: _pickFile)
                  : _FileListView(
                      files: _files,
                      onFileTap: _openFile,
                      onDirectoryTap: _navigateToDirectory,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastPlayedCard extends StatelessWidget {
  const _LastPlayedCard({required this.record, required this.onTap});

  final LastPlayed record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoColors.systemPink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(CupertinoIcons.play_fill, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last Played',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.play_circle_fill,
              color: Colors.white,
              size: 32,
            ),
          ],
        ),
      ),
    );
  }
}

class _FileListView extends StatelessWidget {
  const _FileListView({
    required this.files,
    required this.onFileTap,
    required this.onDirectoryTap,
  });

  final List<FileSystemEntity> files;
  final void Function(String) onFileTap;
  final void Function(String) onDirectoryTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final name = p.basename(file.path);
        final isDirectory = file is Directory;

        IconData icon;
        Color iconColor;

        if (isDirectory) {
          icon = CupertinoIcons.folder_fill;
          iconColor = CupertinoColors.systemBlue;
        } else {
          final ext = p.extension(file.path).toLowerCase();
          if (['.mp4', '.m4v', '.mov', '.avi', '.mkv', '.webm'].contains(ext)) {
            icon = CupertinoIcons.videocam_fill;
            iconColor = CupertinoColors.systemRed;
          } else {
            icon = CupertinoIcons.music_note_2;
            iconColor = CupertinoColors.systemPurple;
          }
        }

        return CupertinoListTile(
          leading: Icon(icon, color: iconColor),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: isDirectory
              ? const Icon(
                  CupertinoIcons.chevron_right,
                  color: CupertinoColors.systemGrey,
                  size: 20,
                )
              : null,
          onTap: () {
            if (isDirectory) {
              onDirectoryTap(file.path);
            } else {
              onFileTap(file.path);
            }
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPickFile});

  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.film,
            size: 64,
            color: CupertinoColors.systemGrey.resolveFrom(context),
          ),
          const SizedBox(height: 16),
          Text(
            'No media files found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add media and same-name lyrics to Documents,\n'
            'or select both files together from Files',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 24),
          CupertinoButton.filled(
            onPressed: onPickFile,
            child: const Text('Pick Media + Lyrics'),
          ),
        ],
      ),
    );
  }
}
