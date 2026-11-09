import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The folders and individual media files shown on the desktop home screen.
class MediaLibrary {
  const MediaLibrary({
    this.folderPaths = const [],
    this.filePaths = const [],
    this.recordingDeviceId = '',
    this.recordingDeviceLabel = '',
    this.iseAppId = '',
    this.iseApiKey = '',
    this.iseApiSecret = '',
    this.themeMode = 'dark',
    this.ratingEnabled = false,
  });

  final List<String> folderPaths;
  final List<String> filePaths;
  final String recordingDeviceId;
  final String recordingDeviceLabel;
  final String iseAppId;
  final String iseApiKey;
  final String iseApiSecret;
  final String themeMode;
  final bool ratingEnabled;

  Map<String, dynamic> toJson() => {
    'folders': folderPaths,
    'files': filePaths,
    'recording_device': {
      'id': recordingDeviceId,
      'label': recordingDeviceLabel,
    },
    'ise_app_id': iseAppId,
    'ise_api_key': iseApiKey,
    'ise_api_secret': iseApiSecret,
    'theme_mode': themeMode,
    'rating_enabled': ratingEnabled,
  };

  factory MediaLibrary.fromJson(Map<String, dynamic> json) {
    final device = json['recording_device'];
    return MediaLibrary(
      folderPaths: _stringList(json['folders']),
      filePaths: _stringList(json['files']),
      recordingDeviceId: device is Map ? _string(device['id']) : '',
      recordingDeviceLabel: device is Map ? _string(device['label']) : '',
      iseAppId: _setting(json, 'ise_app_id', 'ISE_APP_ID'),
      iseApiKey: _setting(json, 'ise_api_key', 'ISE_API_KEY'),
      iseApiSecret: _setting(json, 'ise_api_secret', 'ISE_API_SECRET'),
      themeMode: _themeMode(json['theme_mode']),
      ratingEnabled: json['rating_enabled'] == true,
    );
  }

  MediaLibrary copyWith({
    List<String>? folderPaths,
    List<String>? filePaths,
    String? recordingDeviceId,
    String? recordingDeviceLabel,
    String? iseAppId,
    String? iseApiKey,
    String? iseApiSecret,
    String? themeMode,
    bool? ratingEnabled,
  }) => MediaLibrary(
    folderPaths: folderPaths ?? this.folderPaths,
    filePaths: filePaths ?? this.filePaths,
    recordingDeviceId: recordingDeviceId ?? this.recordingDeviceId,
    recordingDeviceLabel: recordingDeviceLabel ?? this.recordingDeviceLabel,
    iseAppId: iseAppId ?? this.iseAppId,
    iseApiKey: iseApiKey ?? this.iseApiKey,
    iseApiSecret: iseApiSecret ?? this.iseApiSecret,
    themeMode: themeMode ?? this.themeMode,
    ratingEnabled: ratingEnabled ?? this.ratingEnabled,
  );

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static String _themeMode(Object? value) =>
      _string(value) == 'light' ? 'light' : 'dark';

  static String _setting(
    Map<String, dynamic> json,
    String jsonKey,
    String environmentKey,
  ) {
    final stored = _string(json[jsonKey]);
    if (stored.isNotEmpty) return stored;
    return Platform.environment[environmentKey]?.trim() ?? '';
  }
}

/// Persists the library selection in the platform application-support folder.
class MediaLibraryStore {
  MediaLibraryStore._();

  static Future<File> get _file async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}media_library.json');
  }

  static Future<MediaLibrary> read() async {
    try {
      final file = await _file;
      if (!await file.exists()) return const MediaLibrary();
      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return const MediaLibrary();
      return MediaLibrary.fromJson(
        jsonDecode(contents) as Map<String, dynamic>,
      );
    } catch (_) {
      return const MediaLibrary();
    }
  }

  static Future<void> write(MediaLibrary library) async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(library.toJson()));
    } catch (_) {
      // The library is a convenience index; media playback still works when
      // persistence is unavailable.
    }
  }
}
