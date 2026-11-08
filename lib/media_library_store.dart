import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The folders and individual media files shown on the desktop home screen.
class MediaLibrary {
  const MediaLibrary({this.folderPaths = const [], this.filePaths = const []});

  final List<String> folderPaths;
  final List<String> filePaths;

  Map<String, dynamic> toJson() => {'folders': folderPaths, 'files': filePaths};

  factory MediaLibrary.fromJson(Map<String, dynamic> json) => MediaLibrary(
    folderPaths: _stringList(json['folders']),
    filePaths: _stringList(json['files']),
  );

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
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
