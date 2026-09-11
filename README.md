# Camellia Player

![Camellia Player screenshot](s1.png)

Camellia Player is a local audio and video player built with Flutter. The supported targets are **Windows desktop** and **iOS only**.

## Features

- Play local audio and video files
- Load matching subtitle files from the media file's folder
- Open SRT, WebVTT, ASS, or SSA subtitles manually
- Remember the last played file
- Browse files with an iOS-native interface
- Pick files or drag them onto the Windows window
- Show a subtitle/lyrics list and jump between cues
- Record a short voice clip from the Windows player controls

Codec availability depends on the operating system and the media libraries it provides. MP4 with H.264 video and AAC audio is the safest format for both platforms. Windows uses `media_kit`; iOS uses AVFoundation through Flutter's `video_player` package.

## Supported platforms

| Platform | Player and interface |
| --- | --- |
| Windows 10/11 (x64) | Material interface, custom window controls, file picker, and drag and drop |
| iOS 13 or later | Cupertino interface, Files picker, and app Documents browser |

Android, macOS, Linux, and Web are not supported.

## Requirements

### Windows

- Flutter SDK compatible with Dart 3.11 or later
- Visual Studio 2022 with the **Desktop development with C++** workload

### iOS

- macOS with Xcode
- Flutter SDK compatible with Dart 3.11 or later
- CocoaPods
- An Apple development team when running on a physical device or making a signed release build

Check the local toolchains before building:

```console
flutter doctor -v
flutter pub get
```

## Run the app

Windows:

```console
flutter run -d windows
```

iOS Simulator (replace the device name with one installed locally):

```console
flutter devices
flutter run -d "iPhone 16 Pro"
```

To run on a physical iPhone, open `ios/Runner.xcworkspace` in Xcode, select the Runner target, set a signing team and unique bundle identifier, then select the device in Flutter or Xcode.

## Release builds

Windows:

```console
flutter build windows --release
```

The distributable files are written to `build/windows/x64/runner/Release/`. Ship the entire folder, not only the `.exe`, because the application also needs its DLLs and data directory.

iOS Simulator build (no signing required):

```console
flutter build ios --simulator --no-codesign
```

Signed iOS build:

```console
flutter build ios --release
```

For App Store distribution, open `ios/Runner.xcworkspace` and use **Product > Archive** in Xcode.

## Subtitles

When opening a media file, Camellia Player looks in the same folder for a subtitle with the same base name. For example:

```text
lesson.mp4
lesson.srt
```

Recognized companion extensions are `.srt`, `.vtt`, `.ass`, and `.ssa`. In the iOS Documents browser, same-name lyrics are detected automatically. When importing from the iOS Files picker, select the media file and its same-name lyric file together because iOS may expose each selected document through a temporary location. You can also use the subtitle button in the player to choose lyrics later.

## Keyboard shortcuts (Windows)

| Key | Action |
| --- | --- |
| Space | Play or pause |
| Left / Right | Previous / next subtitle cue |
| Home / End | First / last subtitle cue |
| Up / Down | Volume up / down |
| L | Show or hide the lyrics list |
| R | Repeat the current lyric |
| S | Toggle the embedded subtitle track |

## Project structure

```text
lib/
  main.dart                Platform selection and app entry point
  home_screen.dart         Windows home screen
  player_screen.dart       Windows media player
  ios_home_screen.dart     iOS file browser and home screen
  ios_player_screen.dart   iOS media player
  playback_manager.dart    Windows playback state
  subtitle_loader.dart     SRT, VTT, ASS, and SSA parsing
  last_played.dart         Last-played persistence
windows/                   Windows runner
ios/                       iOS runner and Xcode project
```

## Troubleshooting

If Windows reports that Visual Studio is missing, install the **Desktop development with C++** workload and run `flutter doctor -v` again.

If iOS reports that CocoaPods is missing or the pods are stale:

```console
flutter pub get
cd ios
pod install
cd ..
```

Always open `ios/Runner.xcworkspace`, not `Runner.xcodeproj`, after CocoaPods has been installed.

## Quality checks

```console
flutter analyze
flutter test
```
