import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_colors.dart';
import 'custom_title_bar.dart';
import 'last_played.dart';
import 'media_library_store.dart';
import 'player_screen.dart';

const _mediaExtensions = [
  'mp3',
  'aac',
  'wav',
  'mp4',
  'm4v',
  'mkv',
  'webm',
  'mov',
  'avi',
  'wmv',
];
const _subtitleExtensions = ['srt', 'vtt', 'ass', 'ssa'];

enum _LibrarySort { nameAscending, nameDescending, newest }

class LibraryHomeScreen extends StatefulWidget {
  const LibraryHomeScreen({super.key});

  @override
  State<LibraryHomeScreen> createState() => _LibraryHomeScreenState();
}

class _LibraryHomeScreenState extends State<LibraryHomeScreen> {
  final _searchController = TextEditingController();
  MediaLibrary _library = const MediaLibrary();
  Map<String, List<String>> _folderFiles = const {};
  LastPlayed? _lastPlayed;
  _LibrarySort _sort = _LibrarySort.nameAscending;
  bool _gridView = true;
  bool _dragging = false;
  bool _loading = true;
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshSearch);
    _loadLibrary();
    _loadLastPlayed();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  String _key(String path) {
    final value = p.normalize(p.absolute(path));
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  bool _isMedia(String path) => _mediaExtensions.contains(
    p.extension(path).replaceFirst('.', '').toLowerCase(),
  );

  Future<List<String>> _scan(String folder) async {
    final result = <String>[];
    try {
      await for (final entity in Directory(
        folder,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File && _isMedia(entity.path)) result.add(entity.path);
      }
    } catch (_) {}
    return result;
  }

  Future<void> _loadLibrary() async {
    final revision = ++_loadRevision;
    if (mounted) setState(() => _loading = true);
    final stored = await MediaLibraryStore.read();
    final folders = stored.folderPaths
        .where((path) => Directory(path).existsSync())
        .toList();
    final files = stored.filePaths
        .where((path) => File(path).existsSync() && _isMedia(path))
        .toList();
    final scans = <String, List<String>>{};
    for (final folder in folders) {
      scans[folder] = await _scan(folder);
    }
    if (!mounted || revision != _loadRevision) return;
    final clean = MediaLibrary(folderPaths: folders, filePaths: files);
    setState(() {
      _library = clean;
      _folderFiles = scans;
      _loading = false;
    });
    if (folders.length != stored.folderPaths.length ||
        files.length != stored.filePaths.length) {
      await MediaLibraryStore.write(clean);
    }
  }

  Future<void> _loadLastPlayed() async {
    final record = await LastPlayedStore.read();
    if (!mounted) return;
    setState(() {
      _lastPlayed = record != null && File(record.path).existsSync()
          ? record
          : null;
    });
  }

  Future<void> _save(MediaLibrary value) async {
    setState(() => _library = value);
    await MediaLibraryStore.write(value);
  }

  Future<void> _addVideo() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Audio and video',
          extensions: _mediaExtensions,
        ),
      ],
    );
    if (file != null && mounted) await _addFiles([file.path]);
  }

  Future<void> _addFolder() async {
    final folder = await getDirectoryPath(confirmButtonText: 'Add folder');
    if (folder == null || !mounted) return;
    if (_library.folderPaths.any((value) => _key(value) == _key(folder))) {
      _toast('That folder is already in your library.');
      return;
    }
    await MediaLibraryStore.write(
      MediaLibrary(
        folderPaths: [..._library.folderPaths, folder],
        filePaths: _library.filePaths,
      ),
    );
    if (mounted) await _loadLibrary();
  }

  Future<void> _addFiles(Iterable<String> paths) async {
    final known = _library.filePaths.map(_key).toSet();
    final added = <String>[];
    for (final path in paths) {
      if (!_isMedia(path) || !File(path).existsSync()) continue;
      final inFolder = _library.folderPaths.any(
        (folder) => p.isWithin(folder, path),
      );
      if (!inFolder && known.add(_key(path))) added.add(path);
    }
    if (added.isEmpty) {
      _toast('No new supported media files were found.');
      return;
    }
    await _save(
      MediaLibrary(
        folderPaths: _library.folderPaths,
        filePaths: [..._library.filePaths, ...added],
      ),
    );
    _toast('${added.length} item${added.length == 1 ? '' : 's'} added.');
  }

  Future<void> _removeFolder(String path) async {
    final value = MediaLibrary(
      folderPaths: _library.folderPaths
          .where((item) => _key(item) != _key(path))
          .toList(),
      filePaths: _library.filePaths,
    );
    await MediaLibraryStore.write(value);
    if (!mounted) return;
    setState(() {
      _library = value;
      _folderFiles = Map.of(_folderFiles)..remove(path);
    });
  }

  Future<void> _removeFile(String path) => _save(
    MediaLibrary(
      folderPaths: _library.folderPaths,
      filePaths: _library.filePaths
          .where((item) => _key(item) != _key(path))
          .toList(),
    ),
  );

  List<String> get _allFiles {
    final files = <String>[];
    final seen = <String>{};
    for (final group in _folderFiles.values) {
      for (final path in group) {
        if (seen.add(_key(path))) files.add(path);
      }
    }
    for (final path in _library.filePaths) {
      if (seen.add(_key(path))) files.add(path);
    }
    final last = _lastPlayed;
    if (last != null && seen.add(_key(last.path))) files.add(last.path);
    return files;
  }

  bool _matches(String value) {
    final query = _searchController.text.trim().toLowerCase();
    return query.isEmpty || value.toLowerCase().contains(query);
  }

  List<String> get _visibleFolders {
    final value =
        _library.folderPaths
            .where((path) => _matches('$path ${p.basename(path)}'))
            .toList()
          ..sort(
            (a, b) => p
                .basename(a)
                .toLowerCase()
                .compareTo(p.basename(b).toLowerCase()),
          );
    return _sort == _LibrarySort.nameDescending
        ? value.reversed.toList()
        : value;
  }

  List<String> get _visibleFiles {
    final value = _allFiles
        .where((path) => _matches('$path ${p.basename(path)}'))
        .toList();
    switch (_sort) {
      case _LibrarySort.nameAscending:
        value.sort(
          (a, b) => p
              .basename(a)
              .toLowerCase()
              .compareTo(p.basename(b).toLowerCase()),
        );
      case _LibrarySort.nameDescending:
        value.sort(
          (a, b) => p
              .basename(b)
              .toLowerCase()
              .compareTo(p.basename(a).toLowerCase()),
        );
      case _LibrarySort.newest:
        value.sort((a, b) => _modified(b).compareTo(_modified(a)));
    }
    return value;
  }

  DateTime _modified(String path) {
    try {
      return File(path).lastModifiedSync();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> _play(String path) async {
    final file = File(path);
    if (!file.existsSync()) return _toast('File not found: $path');
    final name = p.basename(path);
    final base = path.replaceAll(RegExp(r'\.[^.]+$'), '');
    File? subtitle;
    for (final extension in _subtitleExtensions) {
      final candidate = File('$base.$extension');
      if (candidate.existsSync()) {
        subtitle = candidate;
        break;
      }
    }
    subtitle ??= _closestSubtitle(file.parent.path, p.basename(base));
    final resume = _lastPlayed != null && _key(_lastPlayed!.path) == _key(path);
    if (!resume) {
      await LastPlayedStore.write(LastPlayed(path: path, name: name));
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoFile: file,
          videoPath: name,
          videoName: name,
          subtitleFile: subtitle,
          subtitlePath: subtitle == null ? null : p.basename(subtitle.path),
          initialLyricIndex: resume ? _lastPlayed!.lyricIndex : null,
        ),
      ),
    );
    if (mounted) await _loadLastPlayed();
  }

  File? _closestSubtitle(String directoryPath, String base) {
    try {
      final matches = Directory(directoryPath)
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => _subtitleExtensions.contains(
              p.extension(file.path).replaceFirst('.', '').toLowerCase(),
            ),
          )
          .toList();
      if (matches.length == 1) return matches.first;
      for (final file in matches) {
        final stem = p.basenameWithoutExtension(file.path).toLowerCase();
        if (stem == base.toLowerCase() || stem.startsWith(base.toLowerCase())) {
          return file;
        }
      }
    } catch (_) {}
    return null;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final folders = _visibleFolders;
    final files = _visibleFiles;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          CustomTitleBar(onClose: () async {}),
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (details) async {
                setState(() => _dragging = false);
                await _addFiles(details.files.map((file) => file.path));
              },
              child: Stack(
                children: [
                  const Positioned.fill(child: _Background()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 28, 36, 0),
                    child: Column(
                      children: [
                        _Header(
                          count: _allFiles.length,
                          onAddFolder: _addFolder,
                          onAddVideo: _addVideo,
                        ),
                        const SizedBox(height: 24),
                        _Toolbar(
                          controller: _searchController,
                          sort: _sort,
                          gridView: _gridView,
                          onSort: (value) => setState(() => _sort = value),
                          onView: (value) => setState(() => _gridView = value),
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _LibraryItems(
                                  folders: folders,
                                  files: files,
                                  folderCounts: _folderFiles.map(
                                    (key, value) => MapEntry(key, value.length),
                                  ),
                                  gridView: _gridView,
                                  hasQuery: _searchController.text
                                      .trim()
                                      .isNotEmpty,
                                  lastPlayed: _lastPlayed,
                                  isStandalone: (path) => _library.filePaths
                                      .any((item) => _key(item) == _key(path)),
                                  onPlay: _play,
                                  onRemoveFile: _removeFile,
                                  onRemoveFolder: _removeFolder,
                                  onAddVideo: _addVideo,
                                ),
                        ),
                      ],
                    ),
                  ),
                  if (_dragging) const _DropOverlay(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF080307), Colors.black, Color(0xFF12080F)],
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.onAddFolder,
    required this.onAddVideo,
  });
  final int count;
  final VoidCallback onAddFolder;
  final VoidCallback onAddVideo;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 42,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 32),
            ),
            const SizedBox(width: 17),
            Text(
              'ALL VIDEOS',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          count == 0
              ? 'Add videos or video folders, then play anything in your library.'
              : '$count media item${count == 1 ? '' : 's'} ready to play.',
          style: const TextStyle(
            color: Color(0xFFD8C4CE),
            fontSize: 15,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onAddFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Add Video Folder'),
          style: _buttonStyle(false),
        ),
        FilledButton.icon(
          onPressed: onAddVideo,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Add Video'),
          style: _buttonStyle(true),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, size) => size.maxWidth < 820
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 16), actions],
            )
          : Row(
              children: [
                Expanded(child: copy),
                actions,
              ],
            ),
    );
  }

  ButtonStyle _buttonStyle(bool filled) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22)),
    backgroundColor: WidgetStatePropertyAll(
      filled ? AppColors.camellia : const Color(0xFF542438),
    ),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFFE75889))),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.sort,
    required this.gridView,
    required this.onSort,
    required this.onView,
  });
  final TextEditingController controller;
  final _LibrarySort sort;
  final bool gridView;
  final ValueChanged<_LibrarySort> onSort;
  final ValueChanged<bool> onView;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFD64D7D)),
    );
    final search = TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Search videos and folders...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: controller.clear,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: const Color(0xFF3A202C),
        enabledBorder: border,
        focusedBorder: border,
      ),
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<_LibrarySort>(
          initialValue: sort,
          onSelected: onSort,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _LibrarySort.nameAscending,
              child: Text('Name (A–Z)'),
            ),
            PopupMenuItem(
              value: _LibrarySort.nameDescending,
              child: Text('Name (Z–A)'),
            ),
            PopupMenuItem(
              value: _LibrarySort.newest,
              child: Text('Newest first'),
            ),
          ],
          child: _ControlBox(
            child: Row(
              children: [
                const Icon(Icons.swap_vert_rounded),
                const SizedBox(width: 7),
                Text(switch (sort) {
                  _LibrarySort.nameAscending => 'Sort: Name (A–Z)',
                  _LibrarySort.nameDescending => 'Sort: Name (Z–A)',
                  _LibrarySort.newest => 'Sort: Newest',
                }),
                const SizedBox(width: 9),
                const Icon(Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _ControlBox(
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              _ViewButton(
                icon: Icons.grid_view_rounded,
                selected: gridView,
                onTap: () => onView(true),
              ),
              _ViewButton(
                icon: Icons.view_list_rounded,
                selected: !gridView,
                onTap: () => onView(false),
              ),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, size) => size.maxWidth < 730
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 10), controls],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 20),
                controls,
              ],
            ),
    );
  }
}

class _ControlBox extends StatelessWidget {
  const _ControlBox({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF3A202C),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD64D7D)),
    ),
    child: child,
  );
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 50,
      height: 44,
      decoration: BoxDecoration(
        color: selected ? AppColors.camellia : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon),
    ),
  );
}

class _LibraryItems extends StatelessWidget {
  const _LibraryItems({
    required this.folders,
    required this.files,
    required this.folderCounts,
    required this.gridView,
    required this.hasQuery,
    required this.lastPlayed,
    required this.isStandalone,
    required this.onPlay,
    required this.onRemoveFile,
    required this.onRemoveFolder,
    required this.onAddVideo,
  });
  final List<String> folders;
  final List<String> files;
  final Map<String, int> folderCounts;
  final bool gridView;
  final bool hasQuery;
  final LastPlayed? lastPlayed;
  final bool Function(String) isStandalone;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onRemoveFile;
  final ValueChanged<String> onRemoveFolder;
  final VoidCallback onAddVideo;

  @override
  Widget build(BuildContext context) {
    final count = folders.length + files.length;
    if (count == 0) {
      return _EmptyLibrary(hasQuery: hasQuery, onAddVideo: onAddVideo);
    }
    Widget item(int index) {
      if (index < folders.length) {
        final path = folders[index];
        return _FolderCard(
          path: path,
          count: folderCounts[path] ?? 0,
          grid: gridView,
          onRemove: () => onRemoveFolder(path),
        );
      }
      final path = files[index - folders.length];
      final resume = lastPlayed != null && _samePath(lastPlayed!.path, path)
          ? lastPlayed!.lyricIndex
          : null;
      return _MediaCard(
        path: path,
        grid: gridView,
        resumeIndex: resume,
        onPlay: () => onPlay(path),
        onRemove: isStandalone(path) ? () => onRemoveFile(path) : null,
      );
    }

    if (!gridView) {
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 30),
        itemCount: count,
        itemBuilder: (_, index) => SizedBox(height: 92, child: item(index)),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
      );
    }
    return LayoutBuilder(
      builder: (context, size) {
        final columns = size.maxWidth >= 1400
            ? 4
            : size.maxWidth >= 960
            ? 3
            : size.maxWidth >= 620
            ? 2
            : 1;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 30),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.85,
          ),
          itemBuilder: (_, index) => item(index),
        );
      },
    );
  }

  bool _samePath(String a, String b) => Platform.isWindows
      ? p.normalize(a).toLowerCase() == p.normalize(b).toLowerCase()
      : p.normalize(a) == p.normalize(b);
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.path,
    required this.count,
    required this.grid,
    required this.onRemove,
  });
  final String path;
  final int count;
  final bool grid;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => _CardFrame(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 22, vertical: grid ? 18 : 8),
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, size: 62, color: Color(0xFFFF5D91)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text('$count media item${count == 1 ? '' : 's'}'),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Folder options',
            onSelected: (_) => onRemove(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'remove',
                child: Text('Remove from library'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.path,
    required this.grid,
    required this.resumeIndex,
    required this.onPlay,
    required this.onRemove,
  });
  final String path;
  final bool grid;
  final int? resumeIndex;
  final VoidCallback onPlay;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final info = Padding(
      padding: const EdgeInsets.fromLTRB(15, 7, 8, 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basenameWithoutExtension(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  resumeIndex == null
                      ? p.extension(path).replaceFirst('.', '').toUpperCase()
                      : 'Resume at lyric ${resumeIndex! + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: resumeIndex == null
                        ? const Color(0xFFD9C4CD)
                        : const Color(0xFFFF5D91),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Video options',
            onSelected: (value) {
              if (value == 'play') onPlay();
              if (value == 'remove') onRemove?.call();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'play', child: Text('Play')),
              if (onRemove != null)
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from library'),
                ),
            ],
          ),
        ],
      ),
    );
    return _CardFrame(
      onTap: onPlay,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: grid
            ? Column(
                children: [
                  Expanded(child: _Thumbnail(path)),
                  info,
                ],
              )
            : Row(
                children: [
                  SizedBox(width: 180, child: _Thumbnail(path)),
                  Expanded(child: info),
                ],
              ),
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF713A48), Color(0xFF351B28)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD6547E)),
        ),
        child: child,
      ),
    ),
  );
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail(this.path);
  final String path;
  @override
  Widget build(BuildContext context) {
    final seed = path.hashCode.abs();
    final palettes = [
      const [Color(0xFFFF8290), Color(0xFFB81E62)],
      const [Color(0xFFFF6F91), Color(0xFF702A65)],
      const [Color(0xFFE855A0), Color(0xFF421C50)],
      const [Color(0xFFFF9A76), Color(0xFF9F2E63)],
    ];
    final audio = const [
      '.mp3',
      '.aac',
      '.wav',
    ].contains(p.extension(path).toLowerCase());
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: palettes[seed % palettes.length]),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _PatternPainter(seed)),
          Center(
            child: Icon(
              audio
                  ? Icons.graphic_eq_rounded
                  : Icons.play_circle_outline_rounded,
              size: 58,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter(this.seed);
  final int seed;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF351127).withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(
      Offset(size.width * (0.3 + (seed % 20) / 100), size.height * 0.5),
      size.shortestSide * 0.34,
      paint,
    );
    final path = Path()..moveTo(0, size.height * 0.72);
    path.cubicTo(
      size.width * 0.3,
      size.height * 0.25,
      size.width * 0.65,
      size.height,
      size.width,
      size.height * 0.48,
    );
    canvas.drawPath(path, paint..strokeWidth = 4);
  }

  @override
  bool shouldRepaint(_PatternPainter oldDelegate) => oldDelegate.seed != seed;
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.hasQuery, required this.onAddVideo});
  final bool hasQuery;
  final VoidCallback onAddVideo;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          hasQuery ? Icons.search_off_rounded : Icons.video_library_outlined,
          size: 68,
          color: const Color(0xFFFF6798),
        ),
        const SizedBox(height: 16),
        Text(
          hasQuery ? 'No matching videos or folders' : 'Your library is empty',
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          hasQuery
              ? 'Try another search.'
              : 'Add a video, choose a folder, or drop media files here.',
        ),
        if (!hasQuery) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAddVideo,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Video'),
          ),
        ],
      ],
    ),
  );
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xEE3B1427),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.camellia, width: 2.5),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_rounded, size: 64),
            SizedBox(height: 14),
            Text(
              'Drop to add to your library',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}
