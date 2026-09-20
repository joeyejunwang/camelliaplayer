import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stores zero-based lyric indices for each media file in one JSON file.
class MarkedLyricsStore {
  MarkedLyricsStore._();

  static Future<void> _writeQueue = Future<void>.value();

  static Future<File> get file async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}${Platform.pathSeparator}marked_lyrics.json');
  }

  static Future<Map<String, dynamic>> _readData(File target) async {
    if (!await target.exists()) return <String, dynamic>{};
    final text = await target.readAsString();
    if (text.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(text) as Map<String, dynamic>;
  }

  static List<int> _indicesFor(Map<String, dynamic> data, String mediaPath) {
    final media = data['media'];
    if (media is! Map) return <int>[];
    final indices = media[mediaPath];
    if (indices is! List) return <int>[];
    return indices.whereType<int>().where((index) => index >= 0).toSet().toList()
      ..sort();
  }

  static Future<List<int>> read(String mediaPath, {File? targetFile}) async {
    await _writeQueue;
    final target = targetFile ?? await file;
    return _indicesFor(await _readData(target), mediaPath);
  }

  /// Adds one index without discarding marks for this or other media files.
  /// Returns false when the index was already present.
  static Future<bool> add(String mediaPath, int lyricIndex, {File? targetFile}) {
    if (lyricIndex < 0) {
      throw ArgumentError.value(lyricIndex, 'lyricIndex');
    }
    final operation = _writeQueue.then(
      (_) => _add(mediaPath, lyricIndex, targetFile),
    );
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  static Future<void> flush() => _writeQueue;

  static Future<bool> _add(
    String mediaPath,
    int lyricIndex,
    File? targetFile,
  ) async {
    final target = targetFile ?? await file;
    final data = await _readData(target);
    final rawMedia = data['media'];
    if (rawMedia != null && rawMedia is! Map) {
      throw const FormatException('Invalid marked lyrics file.');
    }
    final media = rawMedia is Map
        ? Map<String, dynamic>.from(rawMedia)
        : <String, dynamic>{};
    if (media.containsKey(mediaPath) && media[mediaPath] is! List) {
      throw const FormatException('Invalid marked lyrics for media.');
    }
    final indices = _indicesFor(data, mediaPath);
    if (indices.contains(lyricIndex)) return false;
    indices.add(lyricIndex);
    indices.sort();
    media[mediaPath] = indices;
    data['version'] = 1;
    data['media'] = media;
    await target.writeAsString(jsonEncode(data), flush: true);
    return true;
  }
}
