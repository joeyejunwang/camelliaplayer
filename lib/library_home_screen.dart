import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import 'app_colors.dart';
import 'app_theme_controller.dart';
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
  String? _openFolderPath;

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
    final clean = stored.copyWith(folderPaths: folders, filePaths: files);
    setState(() {
      _library = clean;
      _folderFiles = scans;
      if (_openFolderPath != null &&
          !folders.any((path) => _key(path) == _key(_openFolderPath!))) {
        _openFolderPath = null;
      }
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
      _library.copyWith(folderPaths: [..._library.folderPaths, folder]),
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
      _library.copyWith(filePaths: [..._library.filePaths, ...added]),
    );
    _toast('${added.length} item${added.length == 1 ? '' : 's'} added.');
  }

  Future<void> _removeFolder(String path) async {
    final value = _library.copyWith(
      folderPaths: _library.folderPaths
          .where((item) => _key(item) != _key(path))
          .toList(),
    );
    await MediaLibraryStore.write(value);
    if (!mounted) return;
    setState(() {
      _library = value;
      _folderFiles = Map.of(_folderFiles)..remove(path);
      if (_openFolderPath != null && _key(_openFolderPath!) == _key(path)) {
        _openFolderPath = null;
      }
    });
  }

  Future<void> _removeFile(String path) => _save(
    _library.copyWith(
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
    return files;
  }

  bool _insideAddedFolder(String path) =>
      _library.folderPaths.any((folder) => p.isWithin(folder, path));

  void _openFolder(String path) {
    _searchController.clear();
    setState(() => _openFolderPath = path);
  }

  void _closeFolder() {
    _searchController.clear();
    setState(() => _openFolderPath = null);
  }

  bool _matches(String value) {
    final query = _searchController.text.trim().toLowerCase();
    return query.isEmpty || value.toLowerCase().contains(query);
  }

  List<String> get _visibleFolders {
    if (_openFolderPath != null) return const [];
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
    final source = _openFolderPath == null
        ? _library.filePaths.where((path) => !_insideAddedFolder(path))
        : (_folderFiles[_openFolderPath] ?? const <String>[]);
    final value = source
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
    final openFolder = _openFolderPath;
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
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                    child: Column(
                      children: [
                        _Header(
                          title: openFolder == null
                              ? 'ALL VIDEOS'
                              : p.basename(openFolder).toUpperCase(),
                          count: openFolder == null
                              ? _allFiles.length
                              : (_folderFiles[openFolder]?.length ?? 0),
                          folderView: openFolder != null,
                          onBack: openFolder == null ? null : _closeFolder,
                          onAddFolder: _addFolder,
                          onAddVideo: _addVideo,
                          onSettings: _showSettings,
                        ),
                        const SizedBox(height: 16),
                        _Toolbar(
                          controller: _searchController,
                          sort: _sort,
                          gridView: _gridView,
                          onSort: (value) => setState(() => _sort = value),
                          onView: (value) => setState(() => _gridView = value),
                        ),
                        const SizedBox(height: 16),
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
                                  onOpenFolder: _openFolder,
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

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LibrarySettingsDialog(
        initialThemeMode: _library.themeMode,
        initialSort: _sort,
        initialConfig: _library,
        onThemeChanged: (value) async {
          AppThemeController.setMode(value);
          await _save(_library.copyWith(themeMode: value));
        },
        onSortChanged: (value) => setState(() => _sort = value),
        onSaveRecorder:
            ({
              required deviceId,
              required deviceLabel,
              required appId,
              required apiKey,
              required apiSecret,
              required ratingEnabled,
            }) async {
              await _save(
                _library.copyWith(
                  recordingDeviceId: deviceId,
                  recordingDeviceLabel: deviceLabel,
                  iseAppId: appId,
                  iseApiKey: apiKey,
                  iseApiSecret: apiSecret,
                  ratingEnabled: ratingEnabled,
                ),
              );
            },
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF080307), Colors.black, Color(0xFF12080F)]
              : const [Color(0xFFFFF8FB), Colors.white, Color(0xFFFFEEF5)],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.count,
    required this.folderView,
    required this.onBack,
    required this.onAddFolder,
    required this.onAddVideo,
    required this.onSettings,
  });
  final String title;
  final int count;
  final bool folderView;
  final VoidCallback? onBack;
  final VoidCallback onAddFolder;
  final VoidCallback onAddVideo;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final copy = Row(
      children: [
        if (onBack != null) ...[
          IconButton(
            onPressed: onBack,
            tooltip: 'Back to all videos',
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  height: 1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                count == 0
                    ? folderView
                          ? 'This folder contains no supported media files.'
                          : 'Add videos or video folders, then play anything in your library.'
                    : folderView
                    ? '$count media item${count == 1 ? '' : 's'} in this folder.'
                    : '$count media item${count == 1 ? '' : 's'} ready to play.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 9,
      runSpacing: 7,
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
        IconButton(
          onPressed: onSettings,
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_rounded, size: 19),
          style: IconButton.styleFrom(
            fixedSize: const Size(40, 40),
            backgroundColor: const Color(0xFF542438),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFE75889)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, size) => size.maxWidth < 820
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 12), actions],
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
    minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
    backgroundColor: WidgetStatePropertyAll(
      filled ? AppColors.camellia : const Color(0xFF542438),
    ),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFFE75889))),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class _LibrarySettingsDialog extends StatefulWidget {
  const _LibrarySettingsDialog({
    required this.initialThemeMode,
    required this.initialSort,
    required this.initialConfig,
    required this.onThemeChanged,
    required this.onSortChanged,
    required this.onSaveRecorder,
  });

  final String initialThemeMode;
  final _LibrarySort initialSort;
  final MediaLibrary initialConfig;
  final Future<void> Function(String value) onThemeChanged;
  final ValueChanged<_LibrarySort> onSortChanged;
  final Future<void> Function({
    required String deviceId,
    required String deviceLabel,
    required String appId,
    required String apiKey,
    required String apiSecret,
    required bool ratingEnabled,
  })
  onSaveRecorder;

  @override
  State<_LibrarySettingsDialog> createState() => _LibrarySettingsDialogState();
}

class _LibrarySettingsDialogState extends State<_LibrarySettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _deviceProbe = AudioRecorder();
  late String _themeMode;
  late _LibrarySort _sort;
  late String _deviceId;
  late bool _ratingEnabled;
  late final TextEditingController _appIdController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiSecretController;
  List<InputDevice> _devices = const [];
  bool _loadingDevices = true;
  bool _saving = false;
  bool _showApiKey = false;
  bool _showApiSecret = false;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _sort = widget.initialSort;
    _deviceId = widget.initialConfig.recordingDeviceId;
    _ratingEnabled = widget.initialConfig.ratingEnabled;
    _appIdController = TextEditingController(
      text: widget.initialConfig.iseAppId,
    );
    _apiKeyController = TextEditingController(
      text: widget.initialConfig.iseApiKey,
    );
    _apiSecretController = TextEditingController(
      text: widget.initialConfig.iseApiSecret,
    );
    _loadInputDevices();
  }

  @override
  void dispose() {
    _deviceProbe.dispose();
    _appIdController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    super.dispose();
  }

  Future<void> _loadInputDevices() async {
    try {
      final devices = await _deviceProbe.listInputDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loadingDevices = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  Future<void> _saveRecorderSettings() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final selected = _devices.where((device) => device.id == _deviceId);
    await widget.onSaveRecorder(
      deviceId: _deviceId,
      deviceLabel: selected.isEmpty ? '' : selected.first.label,
      appId: _appIdController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      apiSecret: _apiSecretController.text.trim(),
      ratingEnabled: _ratingEnabled,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDeviceExists = _devices.any(
      (device) => device.id == _deviceId,
    );
    final dropdownDeviceId = selectedDeviceExists ? _deviceId : '';
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings_rounded, size: 22),
          SizedBox(width: 10),
          Text('Settings'),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'light',
                        icon: Icon(Icons.light_mode_rounded),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: 'dark',
                        icon: Icon(Icons.dark_mode_rounded),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {_themeMode},
                    onSelectionChanged: (selection) {
                      final value = selection.first;
                      setState(() => _themeMode = value);
                      widget.onThemeChanged(value);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_LibrarySort>(
                  initialValue: _sort,
                  decoration: const InputDecoration(
                    labelText: 'Sort order',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _LibrarySort.nameAscending,
                      child: Text('Name (A–Z)'),
                    ),
                    DropdownMenuItem(
                      value: _LibrarySort.nameDescending,
                      child: Text('Name (Z–A)'),
                    ),
                    DropdownMenuItem(
                      value: _LibrarySort.newest,
                      child: Text('Newest first'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _sort = value);
                    widget.onSortChanged(value);
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Voice recording',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('${_devices.length}:$dropdownDeviceId'),
                  initialValue: dropdownDeviceId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Recording source',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _loadingDevices
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Refresh recording sources',
                            onPressed: () {
                              setState(() => _loadingDevices = true);
                              _loadInputDevices();
                            },
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('System default'),
                    ),
                    for (final device in _devices)
                      DropdownMenuItem(
                        value: device.id,
                        child: Text(
                          device.label.isEmpty ? device.id : device.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _deviceId = value ?? ''),
                ),
                const SizedBox(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rating'),
                  subtitle: const Text('Enable rating features'),
                  value: _ratingEnabled,
                  onChanged: (value) => setState(() => _ratingEnabled = value),
                ),
                const SizedBox(height: 24),
                Text(
                  'ISE credentials',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _appIdController,
                  decoration: const InputDecoration(
                    labelText: 'APPID',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: _requiredValue,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiKeyController,
                  obscureText: !_showApiKey,
                  decoration: InputDecoration(
                    labelText: 'APIKey',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: _showApiKey ? 'Hide APIKey' : 'Show APIKey',
                      onPressed: () =>
                          setState(() => _showApiKey = !_showApiKey),
                      icon: Icon(
                        _showApiKey
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                  validator: _requiredValue,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiSecretController,
                  obscureText: !_showApiSecret,
                  decoration: InputDecoration(
                    labelText: 'APISecret',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: _showApiSecret
                          ? 'Hide APISecret'
                          : 'Show APISecret',
                      onPressed: () =>
                          setState(() => _showApiSecret = !_showApiSecret),
                      icon: Icon(
                        _showApiSecret
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                  validator: _requiredValue,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _saveRecorderSettings,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  String? _requiredValue(String? value) =>
      value == null || value.trim().isEmpty ? 'This value is required.' : null;
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
        hintStyle: const TextStyle(fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: controller.clear,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        constraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
        fillColor: Theme.of(context).colorScheme.surfaceContainer,
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
        const SizedBox(width: 9),
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
                const SizedBox(width: 14),
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
    height: 40,
    padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(13),
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
      width: 42,
      height: 36,
      decoration: BoxDecoration(
        color: selected ? AppColors.camellia : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
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
    required this.onOpenFolder,
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
  final ValueChanged<String> onOpenFolder;
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
          onOpen: () => onOpenFolder(path),
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
        itemBuilder: (_, index) => SizedBox(height: 72, child: item(index)),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
      );
    }
    return LayoutBuilder(
      builder: (context, size) {
        final columns = size.maxWidth >= 1080
            ? 5
            : size.maxWidth >= 780
            ? 4
            : size.maxWidth >= 520
            ? 3
            : size.maxWidth >= 340
            ? 2
            : 1;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 30),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.18,
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
    required this.onOpen,
    required this.onRemove,
  });
  final String path;
  final int count;
  final bool grid;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => _CardFrame(
    onTap: onOpen,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: grid ? 8 : 5),
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, size: 34, color: Color(0xFFFF5D91)),
          const SizedBox(width: 9),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count media item${count == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Folder options',
            padding: EdgeInsets.zero,
            iconSize: 18,
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
      padding: const EdgeInsets.fromLTRB(9, 3, 3, 3),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  resumeIndex == null
                      ? p.extension(path).replaceFirst('.', '').toUpperCase()
                      : 'Resume at lyric ${resumeIndex! + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    color: resumeIndex == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : const Color(0xFFFF5D91),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Video options',
            padding: EdgeInsets.zero,
            iconSize: 18,
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
        borderRadius: BorderRadius.circular(14),
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
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: dark
                  ? const [Color(0xFF713A48), Color(0xFF351B28)]
                  : const [Color(0xFFFFE0EA), Color(0xFFFFF5F8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFD6547E)),
          ),
          child: child,
        ),
      ),
    );
  }
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
              size: 32,
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
