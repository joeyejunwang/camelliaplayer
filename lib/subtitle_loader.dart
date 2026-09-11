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
    if (position >= end) return null;
    return text;
  }
}

/// Subtitle loader for SRT, WebVTT, ASS/SSA, and XML-based timed text.
class SubtitleLoader {
  /// Matches SRT and WebVTT timestamps, including WebVTT's optional hours.
  static final _timePattern = RegExp(
    r'((?:\d+:)?\d{2}:\d{2}[,\.]\d{1,3})'
    r'\s*-->\s*'
    r'((?:\d+:)?\d{2}:\d{2}[,\.]\d{1,3})',
  );

  /// Loads and parses subtitles from a file.
  static Future<List<SubtitleEntry>> loadFromFile(
    File file, {
    SubtitleType? format,
  }) async {
    final raw = await file.readAsString();
    return parse(raw, sourcePath: file.path, format: format);
  }

  /// Parses subtitle text. Exposed separately so parsing can be tested without
  /// depending on platform file APIs.
  static List<SubtitleEntry> parse(
    String raw, {
    String sourcePath = '',
    SubtitleType? format,
  }) {
    final type = format ?? _guessType(sourcePath.toLowerCase(), raw);

    // The package parser interprets one- and two-digit fractions as literal
    // milliseconds. Parse line-based formats here so `.5` correctly means
    // 500 ms and `.05` means 50 ms.
    if (type == SubtitleType.srt || type == SubtitleType.vtt) {
      return _parseTimedText(raw);
    }
    if (type == SubtitleType.ssa) return _parseAss(raw);

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
    if (lowerPath.endsWith('.ass') || lowerPath.endsWith('.ssa')) {
      return SubtitleType.ssa;
    }
    return SubtitleType.srt;
  }

  /// Returns true if [text] is a visual placeholder rather than real content.
  static bool _isPlaceholder(String text) {
    return text == '_' || text == '__' || text == '___';
  }

  /// Parses block-based SRT and WebVTT without leaking the next cue number
  /// into the previous cue's text.
  static List<SubtitleEntry> _parseTimedText(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final entries = <SubtitleEntry>[];
    for (final block in normalized.split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n');
      final timingIndex = lines.indexWhere(_timePattern.hasMatch);
      if (timingIndex < 0) continue;
      final match = _timePattern.firstMatch(lines[timingIndex])!;
      final text = lines.sublist(timingIndex + 1).join('\n').trim();
      if (text.isEmpty || _isPlaceholder(text)) continue;
      entries.add(
        SubtitleEntry(
          start: _parseTimestamp(match.group(1)!),
          end: _parseTimestamp(match.group(2)!),
          text: text,
        ),
      );
    }
    return entries;
  }

  static List<SubtitleEntry> _parseSrt(String raw) => _parseTimedText(raw);

  /// Parses the Events section of ASS/SSA files. Styling override tags are
  /// removed because this player renders plain text overlays.
  static List<SubtitleEntry> _parseAss(String raw) {
    final entries = <SubtitleEntry>[];
    var inEvents = false;
    var fields = <String>[];

    for (final rawLine in raw.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('[')) {
        inEvents = line.toLowerCase() == '[events]';
        continue;
      }
      if (!inEvents) continue;

      if (line.toLowerCase().startsWith('format:')) {
        fields = line
            .substring(line.indexOf(':') + 1)
            .split(',')
            .map((field) => field.trim().toLowerCase())
            .toList();
        continue;
      }
      if (!line.toLowerCase().startsWith('dialogue:') || fields.isEmpty) {
        continue;
      }

      final values = _splitCommaFields(
        line.substring(line.indexOf(':') + 1).trimLeft(),
        fields.length,
      );
      final startIndex = fields.indexOf('start');
      final endIndex = fields.indexOf('end');
      final textIndex = fields.indexOf('text');
      if (values.length != fields.length ||
          startIndex < 0 ||
          endIndex < 0 ||
          textIndex < 0) {
        continue;
      }

      final text = values[textIndex]
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .trim();
      if (text.isEmpty || _isPlaceholder(text)) continue;
      entries.add(
        SubtitleEntry(
          start: _parseTimestamp(values[startIndex]),
          end: _parseTimestamp(values[endIndex]),
          text: text,
        ),
      );
    }
    return entries;
  }

  static List<String> _splitCommaFields(String value, int fieldCount) {
    final result = <String>[];
    var remainder = value;
    for (var i = 1; i < fieldCount; i++) {
      final comma = remainder.indexOf(',');
      if (comma < 0) return const [];
      result.add(remainder.substring(0, comma));
      remainder = remainder.substring(comma + 1);
    }
    result.add(remainder);
    return result;
  }

  /// Parses a timestamp like "00:01:47,039" or "1:02:03.456".
  /// Handles both comma and period as decimal separators.
  static Duration _parseTimestamp(String raw) {
    // Normalize comma → period
    final normalized = raw.replaceAll(',', '.');

    // Split into parts. ASS permits a one-digit hour; WebVTT may omit hours.
    final parts = normalized.split(':');
    if (parts.length != 2 && parts.length != 3) return Duration.zero;

    final h = parts.length == 3 ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = int.tryParse(parts[parts.length - 2]) ?? 0;

    // Milliseconds part may use either '.' or ','
    final secPart = parts.last.replaceAll(',', '.');
    final secParts = secPart.split('.');
    final s = int.tryParse(secParts[0]) ?? 0;
    final fraction = secParts.length > 1 ? secParts[1] : '';
    final milliseconds = fraction.isEmpty
        ? 0
        : int.tryParse(fraction.padRight(3, '0').substring(0, 3)) ?? 0;

    return Duration(
      hours: h,
      minutes: m,
      seconds: s,
      milliseconds: milliseconds,
    );
  }
}
