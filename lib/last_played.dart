import 'dart:convert';
import 'dart:io';

/// Persisted record of the last media file played by the user.
///
/// Stored as a small JSON file next to the app executable so it survives
/// restarts without requiring any extra plugins (no path_provider needed).
class LastPlayed {
  LastPlayed({required this.path, required this.name, required this.timestamp});

  final String path;
  final String name;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LastPlayed.fromJson(Map<String, dynamic> json) => LastPlayed(
        path: json['path'] as String,
        name: json['name'] as String,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Reads / writes the last-played JSON record.
class LastPlayedStore {
  LastPlayedStore._();

  /// `last_played.json` next to the running executable.
  static File get _file {
    // On Windows the executable lives in `build\...\.exe`; the directory
    // is writable on dev machines. Falls back to current dir if null.
    final exe = Platform.resolvedExecutable;
    final dir = exe.isNotEmpty ? File(exe).parent.path : Directory.current.path;
    return File('$dir${Platform.pathSeparator}last_played.json');
  }

  static Future<LastPlayed?> read() async {
    try {
      final f = _file;
      if (!f.existsSync()) return null;
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
      final f = _file;
      await f.writeAsString(jsonEncode(record.toJson()));
    } catch (_) {
      // Swallow write errors — last-played is best-effort.
    }
  }

  static Future<void> clear() async {
    try {
      final f = _file;
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
