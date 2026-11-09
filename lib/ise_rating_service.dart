import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'media_library_store.dart';

enum IseRatingStatus { idle, loading, success, failure }

@immutable
class IseRatingState {
  const IseRatingState({
    this.status = IseRatingStatus.idle,
    this.wavPath,
    this.reference = '',
    this.summary = const {},
    this.words = const [],
    this.error,
  });

  final IseRatingStatus status;
  final String? wavPath;
  final String reference;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> words;
  final String? error;
}

class IseRatingService {
  IseRatingService._();

  static const _host = 'ise-api.xfyun.cn';
  static const _path = '/v2/open-ise';
  static const _frameBytes = 1280;
  static final ValueNotifier<IseRatingState> ratingState = ValueNotifier(
    const IseRatingState(),
  );

  static void clearRating() {
    ratingState.value = const IseRatingState();
  }

  static Future<void> rateAndSave({
    required String wavPath,
    required String reference,
  }) async {
    ratingState.value = IseRatingState(
      wavPath: wavPath,
      reference: reference.trim(),
    );
    final settings = await MediaLibraryStore.read();
    if (!settings.ratingEnabled) return;
    ratingState.value = IseRatingState(
      status: IseRatingStatus.loading,
      wavPath: wavPath,
      reference: reference.trim(),
    );
    final output = File(p.setExtension(wavPath, '.json'));
    try {
      final appId = settings.iseAppId.trim();
      final apiKey = settings.iseApiKey.trim();
      final apiSecret = settings.iseApiSecret.trim();
      if (appId.isEmpty || apiKey.isEmpty || apiSecret.isEmpty) {
        throw StateError('ISE credentials are incomplete.');
      }
      final text = reference.trim();
      if (text.isEmpty) throw StateError('The reference subtitle is empty.');
      final pcm = await _readPcm(File(wavPath));
      final packet = await _send(
        appId: appId,
        apiKey: apiKey,
        apiSecret: apiSecret,
        pcm: pcm,
        reference: text,
      );
      final data = packet['data'] as Map<String, dynamic>? ?? const {};
      final encodedXml = data['data'] as String?;
      if (encodedXml == null || encodedXml.isEmpty) {
        throw StateError('ISE returned no assessment payload.');
      }
      final xmlBytes = base64Decode(encodedXml);
      final parsed = _parseXml(utf8.decode(xmlBytes, allowMalformed: true));
      final savedResult = <String, dynamic>{
        'ok': true,
        'sid': packet['sid'],
        'reference': text,
        'wav_file': p.basename(wavPath),
        'rated_at': DateTime.now().toUtc().toIso8601String(),
        ...parsed,
      };
      await _writeJson(output, savedResult);
      if (_isCurrent(wavPath)) {
        ratingState.value = IseRatingState(
          status: IseRatingStatus.success,
          wavPath: wavPath,
          reference: text,
          summary: Map<String, dynamic>.from(savedResult['summary'] as Map),
          words: (savedResult['words'] as List)
              .map((word) => Map<String, dynamic>.from(word as Map))
              .toList(growable: false),
        );
      }
    } catch (error) {
      final message = _safeError(error);
      if (_isCurrent(wavPath)) {
        ratingState.value = IseRatingState(
          status: IseRatingStatus.failure,
          wavPath: wavPath,
          reference: reference.trim(),
          error: message,
        );
      }
      await _writeJson(output, {
        'ok': false,
        'reference': reference.trim(),
        'wav_file': p.basename(wavPath),
        'rated_at': DateTime.now().toUtc().toIso8601String(),
        'error': message,
      });
    }
  }

  static bool _isCurrent(String wavPath) =>
      ratingState.value.wavPath == wavPath;

  static Future<Uint8List> _readPcm(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 44 ||
        !_matchesAscii(bytes, 0, 'RIFF') ||
        !_matchesAscii(bytes, 8, 'WAVE')) {
      throw const FormatException('The recording is not a PCM WAV file.');
    }
    final view = ByteData.sublistView(bytes);
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? audioFormat;
    Uint8List? pcm;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final size = view.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      final end = start + size;
      if (end > bytes.length) break;
      if (_matchesAscii(bytes, offset, 'fmt ') && size >= 16) {
        audioFormat = view.getUint16(start, Endian.little);
        channels = view.getUint16(start + 2, Endian.little);
        sampleRate = view.getUint32(start + 4, Endian.little);
        bitsPerSample = view.getUint16(start + 14, Endian.little);
      } else if (_matchesAscii(bytes, offset, 'data')) {
        pcm = Uint8List.sublistView(bytes, start, end);
      }
      offset = end + (size.isOdd ? 1 : 0);
    }
    if (audioFormat != 1 ||
        channels != 1 ||
        sampleRate != 16000 ||
        bitsPerSample != 16 ||
        pcm == null ||
        pcm.isEmpty) {
      throw FormatException(
        'ISE requires 16 kHz, 16-bit, mono PCM WAV audio; found '
        '${sampleRate ?? 0} Hz, ${channels ?? 0} channel(s), '
        '${bitsPerSample ?? 0}-bit.',
      );
    }
    return pcm;
  }

  static Future<Map<String, dynamic>> _send({
    required String appId,
    required String apiKey,
    required String apiSecret,
    required Uint8List pcm,
    required String reference,
  }) async {
    final socket = await WebSocket.connect(
      _authorizedUrl(apiKey, apiSecret),
    ).timeout(const Duration(seconds: 25));
    final result = Completer<Map<String, dynamic>>();
    late final StreamSubscription<dynamic> subscription;
    subscription = socket.listen(
      (message) {
        try {
          final packet = jsonDecode(message as String) as Map<String, dynamic>;
          final code = packet['code'] as int? ?? 0;
          if (code != 0) {
            if (!result.isCompleted) {
              result.completeError(
                StateError(
                  'ISE error $code: ${packet['message'] ?? 'Unknown'}',
                ),
              );
            }
            return;
          }
          final data = packet['data'] as Map<String, dynamic>?;
          if (data?['status'] == 2 && !result.isCompleted) {
            result.complete(packet);
          }
        } catch (error) {
          if (!result.isCompleted) result.completeError(error);
        }
      },
      onError: (Object error) {
        if (!result.isCompleted) result.completeError(error);
      },
      onDone: () {
        if (!result.isCompleted) {
          result.completeError(
            StateError('ISE closed before returning a result.'),
          );
        }
      },
    );
    try {
      final paper = '\uFEFF[content]\n${reference.trim()}\n';
      socket.add(
        jsonEncode({
          'common': {'app_id': appId},
          'business': {
            'sub': 'ise',
            'ent': 'en_vip',
            'category': 'read_sentence',
            'cmd': 'ssb',
            'text': paper,
            'tte': 'utf-8',
            'ttp_skip': true,
            'aue': 'raw',
            'auf': 'audio/L16;rate=16000',
            'rstcd': 'utf8',
            'rst': 'entirety',
            'ise_unite': '1',
            'extra_ability': 'multi_dimension',
          },
          'data': {'status': 0},
        }),
      );
      for (
        var offset = 0;
        offset < pcm.length && !result.isCompleted;
        offset += _frameBytes
      ) {
        final end = (offset + _frameBytes).clamp(0, pcm.length).toInt();
        final chunk = Uint8List.sublistView(pcm, offset, end);
        socket.add(
          jsonEncode({
            'business': {'cmd': 'auw', 'aus': offset == 0 ? 1 : 2},
            'data': {'status': 1, 'data': base64Encode(chunk)},
          }),
        );
        await Future<void>.delayed(
          Duration(milliseconds: (chunk.length * 1000 / 32000).round()),
        );
      }
      if (!result.isCompleted) {
        socket.add(
          jsonEncode({
            'business': {'cmd': 'auw', 'aus': 4},
            'data': {'status': 2, 'data': ''},
          }),
        );
      }
      return await result.future.timeout(const Duration(seconds: 45));
    } finally {
      await subscription.cancel();
      await socket.close();
    }
  }

  static String _authorizedUrl(String apiKey, String apiSecret) {
    final date = HttpDate.format(DateTime.now().toUtc());
    final origin = 'host: $_host\ndate: $date\nGET $_path HTTP/1.1';
    final signature = base64Encode(
      Hmac(sha256, utf8.encode(apiSecret)).convert(utf8.encode(origin)).bytes,
    );
    final authorization = base64Encode(
      utf8.encode(
        'api_key="$apiKey", algorithm="hmac-sha256", '
        'headers="host date request-line", signature="$signature"',
      ),
    );
    return Uri(
      scheme: 'wss',
      host: _host,
      path: _path,
      queryParameters: {
        'authorization': authorization,
        'date': date,
        'host': _host,
      },
    ).toString();
  }

  static Map<String, dynamic> _parseXml(String source) {
    final document = XmlDocument.parse(source.replaceFirst('\uFEFF', ''));
    final elements = document.descendants.whereType<XmlElement>();
    XmlElement? summaryNode;
    for (final element in elements) {
      if (element.getAttribute('total_score') != null) {
        summaryNode = element;
        break;
      }
    }
    final words = <Map<String, dynamic>>[];
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'word' ||
          element.getAttribute('rec_node_type') == 'sil') {
        continue;
      }
      final word = (element.getAttribute('content') ?? '').trim();
      if (word.isEmpty || word.toLowerCase() == 'sil') continue;
      final dp = element.getAttribute('dp_message');
      words.add({
        'word': word,
        'score': _number(element.getAttribute('total_score')),
        'dp_message': dp,
        'status': _describeDp(dp),
        'start_seconds': _frameSeconds(element.getAttribute('beg_pos')),
        'end_seconds': _frameSeconds(element.getAttribute('end_pos')),
      });
    }
    return {
      'summary': {
        'total_score': _number(summaryNode?.getAttribute('total_score')),
        'accuracy_score': _number(summaryNode?.getAttribute('accuracy_score')),
        'fluency_score': _number(summaryNode?.getAttribute('fluency_score')),
        'integrity_score': _number(
          summaryNode?.getAttribute('integrity_score'),
        ),
        'standard_score': _number(summaryNode?.getAttribute('standard_score')),
        'is_rejected': summaryNode?.getAttribute('is_rejected'),
        'except_info': summaryNode?.getAttribute('except_info'),
      },
      'words': words,
    };
  }

  static double? _number(String? value) =>
      value == null ? null : double.tryParse(value);

  static double? _frameSeconds(String? value) {
    final number = _number(value);
    return number == null ? null : number / 100;
  }

  static String _describeDp(String? value) {
    final number = int.tryParse(value ?? '');
    if (number == null) return 'Not provided';
    if (number == 0) return 'Read / 正常读出';
    final names = <String>[];
    if ((number & 16) != 0) names.add('Omitted / 漏读');
    if ((number & 32) != 0) names.add('Inserted / 增读');
    if ((number & 64) != 0) names.add('Repeated / 回读');
    if ((number & 128) != 0) names.add('Substituted / 替换');
    return names.isEmpty ? 'Unknown ($number)' : names.join(', ');
  }

  static bool _matchesAscii(Uint8List bytes, int start, String value) {
    if (start < 0 || start + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[start + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static Future<void> _writeJson(File file, Map<String, dynamic> value) async {
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(value));
  }

  static String _safeError(Object error) {
    final value = error.toString();
    if (value.contains('authorization=') || value.contains('api_key=')) {
      return 'ISE connection failed. Check credentials and network access.';
    }
    return value;
  }
}
