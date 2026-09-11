import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persisted record of the last media file played by the user.
///
/// Stored as a small JSON file in the platform's application-support
/// directory so it remains writable in installed Windows and iOS builds.
class LastPlayed {
  LastPlayed({
    required this.path,
    required this.name,
    required this.timestamp,
    this.lyricIndex,
  });

  final String path;
  final String name;
  final DateTime timestamp;
  final int? lyricIndex;

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'timestamp': timestamp.toIso8601String(),
    'lyricIndex': lyricIndex,
  };

  factory LastPlayed.fromJson(Map<String, dynamic> json) => LastPlayed(
    path: json['path'] as String,
    name: json['name'] as String,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    lyricIndex: json['lyricIndex'] is int ? json['lyricIndex'] as int : null,
  );
}

/// Reads / writes the last-played JSON record.
class LastPlayedStore {
  LastPlayedStore._();

  static Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}last_played.json');
  }

  static Future<LastPlayed?> read() async {
    try {
      final f = await _file;
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      if (txt.trim().isEmpty) return null;
      final json = jsonDecode(txt) as Map<String, dynamic>;
      return LastPlayed.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(LastPlayed record) async {
    try {
      final f = await _file;
      await f.writeAsString(jsonEncode(record.toJson()));
    } catch (_) {
      // Swallow write errors — last-played is best-effort.
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file;
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
