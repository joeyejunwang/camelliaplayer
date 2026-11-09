import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_player/media_library_store.dart';

void main() {
  test('media library config preserves recorder and ISE settings', () {
    const library = MediaLibrary(
      folderPaths: ['videos'],
      filePaths: ['lesson.mp4'],
      recordingDeviceId: 'microphone-id',
      recordingDeviceLabel: 'USB Microphone',
      iseAppId: 'app-id',
      iseApiKey: 'api-key',
      iseApiSecret: 'api-secret',
      themeMode: 'light',
      ratingEnabled: true,
    );

    final restored = MediaLibrary.fromJson(library.toJson());

    expect(restored.recordingDeviceId, 'microphone-id');
    expect(restored.recordingDeviceLabel, 'USB Microphone');
    expect(restored.iseAppId, 'app-id');
    expect(restored.iseApiKey, 'api-key');
    expect(restored.iseApiSecret, 'api-secret');
    expect(restored.themeMode, 'light');
    expect(restored.ratingEnabled, isTrue);
  });

  test('copyWith keeps recorder settings during library changes', () {
    const library = MediaLibrary(
      recordingDeviceId: 'microphone-id',
      iseAppId: 'app-id',
      iseApiKey: 'api-key',
      iseApiSecret: 'api-secret',
      ratingEnabled: true,
    );

    final changed = library.copyWith(filePaths: ['lesson.mp4']);

    expect(changed.filePaths, ['lesson.mp4']);
    expect(changed.recordingDeviceId, 'microphone-id');
    expect(changed.iseAppId, 'app-id');
    expect(changed.iseApiKey, 'api-key');
    expect(changed.iseApiSecret, 'api-secret');
    expect(changed.themeMode, 'dark');
    expect(changed.ratingEnabled, isTrue);
  });

  test('unknown or missing theme values default to dark', () {
    expect(MediaLibrary.fromJson(const {}).themeMode, 'dark');
    expect(
      MediaLibrary.fromJson(const {'theme_mode': 'system'}).themeMode,
      'dark',
    );
  });

  test('rating defaults to disabled for existing config files', () {
    expect(MediaLibrary.fromJson(const {}).ratingEnabled, isFalse);
  });
}
