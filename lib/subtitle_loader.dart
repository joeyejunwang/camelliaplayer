import 'dart:io';

import 'package:subtitle/subtitle.dart';

/// Single subtitle cue with absolute timeline.
class SubtitleEntry {
  SubtitleEntry({required this.start, required this.end, required this.text});
  final Duration start;
  final Duration end;
  final String text;

  /// Returns the cue text if [position] falls inside this cue, otherwise null.
  String? textAt(Duration position) {
    if (position < start) return null;
    if (position > end) return null;
    return text;
  }
}

/// Lightweight loader that wraps the `subtitle` package and falls back to a
/// hand-rolled SRT parser when the file format isn't recognized.
class SubtitleLoader {
  /// Regex matches SRT-style timestamp lines. Allows 1-2 digit hours to be
  /// tolerant of malformed files (e.g. "00:00:0,500").
  static final _timePattern = RegExp(
    r'([\d]{1,2}:[\d]{2}:[\d]{2}[,\.]\d{1,3})'
    r'\s*-->\s*'
    r'([\d]{1,2}:[\d]{2}:[\d]{2}[,\.]\d{1,3})',
  );

  /// Loads subtitles from a file. Tries the `subtitle` package first, then
  /// falls back to the hand-rolled parser.
  static Future<List<SubtitleEntry>> loadFromFile(
    File file, {
    SubtitleType? format,
  }) async {
    final raw = await file.readAsString();
    final ext = file.path.toLowerCase();
    final type = format ?? _guessType(ext, raw);
    try {
      final object = SubtitleObject(data: raw, type: type);
      final parser = SubtitleParser(object);
      final parsed = parser.parsing(shouldNormalizeText: false);
      return [
        for (final p in parsed)
          if (!_isPlaceholder(p.data.trim()))
            SubtitleEntry(start: p.start, end: p.end, text: p.data.trim()),
      ];
    } catch (_) {
      return _parseSrt(raw);
    }
  }

  static SubtitleType _guessType(String lowerPath, String content) {
    if (lowerPath.endsWith('.vtt') || content.trimLeft().startsWith('WEBVTT')) {
      return SubtitleType.vtt;
    }
    if (lowerPath.endsWith('.ttml') || lowerPath.endsWith('.dfxp')) {
      return SubtitleType.ttml;
    }
    return SubtitleType.srt;
  }

  /// Returns true if [text] is a visual placeholder rather than real content.
  static bool _isPlaceholder(String text) {
    return text == '_' || text == '__' || text == '___';
  }

  /// Hand-rolled SRT parser. Normalizes both comma and period decimal
  /// separators in milliseconds, and accepts 1-2 digit hour fields.
  static List<SubtitleEntry> _parseSrt(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.trim())
        .toList();

    final entries = <SubtitleEntry>[];
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // Skip blank lines
      if (line.isEmpty) {
        i++;
        continue;
      }

      final match = _timePattern.firstMatch(line);
      if (match == null) {
        i++;
        continue;
      }

      final start = _parseTimestamp(match.group(1)!);
      final end = _parseTimestamp(match.group(2)!);
      i++;

      // Collect text lines until the next timestamp or end of file
      final buffer = StringBuffer();
      while (i < lines.length && !_timePattern.hasMatch(lines[i])) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(lines[i]);
        i++;
      }

      final text = buffer.toString().trim();
      if (text.isEmpty || _isPlaceholder(text)) continue;

      entries.add(SubtitleEntry(start: start, end: end, text: text));
    }

    return entries;
  }

  /// Parses a timestamp like "00:01:47,039" or "1:02:03.456".
  /// Handles both comma and period as decimal separators.
  static Duration _parseTimestamp(String raw) {
    // Normalize comma → period
    final normalized = raw.replaceAll(',', '.');

    // Split into parts
    final parts = normalized.split(':');
    if (parts.length != 3) {
      return Duration.zero;
    }

    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    // Milliseconds part may use either '.' or ','
    final secPart = parts[2].replaceAll(',', '.');
    final secParts = secPart.split('.');
    final s = int.tryParse(secParts[0]) ?? 0;
    final ms = secParts.length > 1
        ? (int.tryParse(secParts[1]) ?? 0)
        : 0;

    return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
  }
}
