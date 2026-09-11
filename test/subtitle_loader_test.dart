import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_player/subtitle_loader.dart';

void main() {
  group('SubtitleLoader', () {
    test('parses SRT cues without including cue numbers in the text', () {
      const source = '''
1
00:00:00,500 --> 00:00:01,500
First line

2
00:00:02,000 --> 00:00:03,000
Second line
''';

      final entries = SubtitleLoader.parse(source, sourcePath: 'captions.srt');

      expect(entries, hasLength(2));
      expect(entries[0].text, 'First line');
      expect(entries[1].text, 'Second line');
    });

    test('scales short timestamp fractions correctly', () {
      const source = '''
00:00.5 --> 00:01.05
Fractional timing
''';

      final entries = SubtitleLoader.parse(source, sourcePath: 'captions.vtt');

      expect(entries.single.start, const Duration(milliseconds: 500));
      expect(entries.single.end, const Duration(milliseconds: 1050));
    });

    test('treats a cue end as exclusive', () {
      final entry = SubtitleEntry(
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 2),
        text: 'Cue',
      );

      expect(entry.textAt(const Duration(milliseconds: 1999)), 'Cue');
      expect(entry.textAt(const Duration(seconds: 2)), isNull);
    });

    test('parses ASS dialogue text and strips style overrides', () {
      const source = r'''
[Script Info]
Title: Example

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.50,0:00:03.25,Default,,0,0,0,,{\i1}Hello\Nworld
''';

      final entries = SubtitleLoader.parse(source, sourcePath: 'captions.ass');

      expect(entries, hasLength(1));
      expect(entries.single.start, const Duration(milliseconds: 1500));
      expect(entries.single.end, const Duration(milliseconds: 3250));
      expect(entries.single.text, 'Hello\nworld');
    });
  });
}
