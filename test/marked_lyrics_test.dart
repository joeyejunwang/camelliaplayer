import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_player/marked_lyrics.dart';

void main() {
  test('marked lyrics accumulate per media without duplicates', () async {
    final directory = await Directory.systemTemp.createTemp('marked_lyrics_test_');
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final target = File('${directory.path}${Platform.pathSeparator}marks.json');

    expect(
      await MarkedLyricsStore.add('movie-a.mp4', 10, targetFile: target),
      isTrue,
    );
    expect(
      await MarkedLyricsStore.add('movie-a.mp4', 2, targetFile: target),
      isTrue,
    );
    expect(
      await MarkedLyricsStore.add('movie-a.mp4', 10, targetFile: target),
      isFalse,
    );
    expect(
      await MarkedLyricsStore.add('movie-b.mp4', 5, targetFile: target),
      isTrue,
    );

    expect(
      await MarkedLyricsStore.read('movie-a.mp4', targetFile: target),
      [2, 10],
    );
    expect(
      await MarkedLyricsStore.read('movie-b.mp4', targetFile: target),
      [5],
    );

    final data = jsonDecode(await target.readAsString()) as Map<String, dynamic>;
    expect((data['media'] as Map<String, dynamic>).length, 2);
  });
}
