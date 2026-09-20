import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Uses zero-based indices in the app and one-based lyric numbers in JSON.
class MarkedLyricsStore {
  MarkedLyricsStore._();

  static const _encoder = JsonEncoder.withIndent('  ');
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
    return indices
        .whereType<int>()
        .where((number) => number >= 1)
        .map((number) => number - 1)
        .toSet()
        .toList()
      ..sort();
  }

  static Future<T> _enqueue<T>(Future<T> Function() work) {
    final operation = _writeQueue.then((_) => work());
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static Future<List<int>> read(String mediaPath, {File? targetFile}) =>
      _enqueue(() => _read(mediaPath, targetFile));

  static Future<List<int>> _read(String mediaPath, File? targetFile) async {
    final target = targetFile ?? await file;
    final source = await _readData(target);
    if (source.isEmpty) return <int>[];
    final data = _cleanData(source);
    if (_hasMetadata(source)) await _writeData(target, data);
    return _indicesFor(data, mediaPath);
  }

  /// Adds one index without discarding marks for this or other media files.
  /// Returns false when the index was already present.
  static Future<bool> add(
    String mediaPath,
    int lyricIndex, {
    File? targetFile,
  }) {
    if (lyricIndex < 0) {
      throw ArgumentError.value(lyricIndex, 'lyricIndex');
    }
    return _enqueue(() => _add(mediaPath, lyricIndex, targetFile));
  }

  static Future<void> flush() => _writeQueue;

  /// Removes one index without changing marks for other media files.
  /// Returns false when that index was not marked.
  static Future<bool> remove(
    String mediaPath,
    int lyricIndex, {
    File? targetFile,
  }) {
    if (lyricIndex < 0) {
      throw ArgumentError.value(lyricIndex, 'lyricIndex');
    }
    return _enqueue(() => _remove(mediaPath, lyricIndex, targetFile));
  }

  static bool _hasMetadata(Map<String, dynamic> data) =>
      data.containsKey('version') || data.containsKey('lyricNumbersStartAt');

  static Map<String, dynamic> _cleanData(Map<String, dynamic> data) {
    final sourceMedia = data['media'];
    if (sourceMedia != null && sourceMedia is! Map) {
      throw const FormatException('Invalid marked lyrics file.');
    }
    final media = <String, dynamic>{};
    if (sourceMedia is Map) {
      final paths = sourceMedia.keys.toList();
      if (paths.any((path) => path is! String)) {
        throw const FormatException('Invalid media path in marked lyrics.');
      }
      paths.cast<String>().sort();
      for (final path in paths.cast<String>()) {
        if (sourceMedia[path] is! List) {
          throw const FormatException('Invalid marked lyrics for media.');
        }
        media[path] = [for (final index in _indicesFor(data, path)) index + 1];
      }
    }
    return <String, dynamic>{'media': media};
  }

  static Future<void> _writeData(File target, Map<String, dynamic> data) =>
      target.writeAsString(
        '${_encoder.convert(_cleanData(data))}\n',
        flush: true,
      );

  static Map<String, dynamic> _mediaFor(Map<String, dynamic> data) {
    return data['media'] as Map<String, dynamic>;
  }

  static Future<bool> _add(
    String mediaPath,
    int lyricIndex,
    File? targetFile,
  ) async {
    final target = targetFile ?? await file;
    final source = await _readData(target);
    final data = _cleanData(source);
    final media = _mediaFor(data);
    final indices = _indicesFor(data, mediaPath);
    if (indices.contains(lyricIndex)) {
      if (_hasMetadata(source)) await _writeData(target, data);
      return false;
    }
    indices.add(lyricIndex);
    indices.sort();
    media[mediaPath] = [for (final index in indices) index + 1];
    await _writeData(target, data);
    return true;
  }

  static Future<bool> _remove(
    String mediaPath,
    int lyricIndex,
    File? targetFile,
  ) async {
    final target = targetFile ?? await file;
    final source = await _readData(target);
    final data = _cleanData(source);
    final media = _mediaFor(data);
    final indices = _indicesFor(data, mediaPath);
    if (!indices.remove(lyricIndex)) {
      if (_hasMetadata(source)) await _writeData(target, data);
      return false;
    }
    if (indices.isEmpty) {
      media.remove(mediaPath);
    } else {
      media[mediaPath] = [for (final index in indices) index + 1];
    }
    await _writeData(target, data);
    return true;
  }
}
