# Camellia Player

![App Screenshot](s1.png)

A simple, modern Flutter **audio and video player** for **Windows desktop** (and Web).
Pick a local MP3 or video file and play. Matching subtitle files in the same folder are loaded automatically.

## Features

- Pick local audio (mp3, wav) or video files (mp4, mkv, webm, mov, …)
- **Drag & drop** an `.mp4` / `.wav` / `.mp3` file anywhere on the home window to start playing
- **"Last played" card** remembers the most recent media file; one click replays it (persisted to `last_played.json` next to the executable)
- MP3 playback displays a music icon and filename, with the same playback and lyric controls as video
- Optional subtitle file (SRT, VTT, ASS/SSA) — toggleable overlay
- Native-feeling player UI powered by [`chewie`](https://pub.dev/packages/chewie) + [`video_player`](https://pub.dev/packages/video_player)
- Material 3 light/dark theme
- Runs on Windows desktop and Chrome/Edge web (handy while you don't have Visual Studio installed)

## Prerequisites

| Platform | Required |
| --- | --- |
| Windows desktop | Flutter SDK (3.x) **and** Visual Studio 2022 with the *"Desktop development with C++"* workload |
| Web | Flutter SDK + any modern Chromium-based browser |

Verify with:

```bash
flutter doctor
```

If you see `Visual Studio not installed`, install Visual Studio 2022 Community with the C++ desktop workload, then re-run `flutter doctor`.

## Run

```bash
flutter clean
rmdir /s /q build

# Windows desktop
flutter run -d windows

# Or, in Chrome while you set up Visual Studio
flutter run -d chrome
```

## Build a release executable

```bash
flutter build windows --release
build\windows\x64\runner\Release
cp -r build/windows/x64/runner/Release/* /d/Working/CamelliaPlayerRelease
```

The output will be in `build/windows/runner/Release/`.

## Continuous Integration

A GitHub Actions workflow builds the Windows release on every push:

- Workflow: `.github/workflows/build-windows.yml`
- Runner: `windows-latest`
- Command: `flutter build windows --release`
- Artifact: `camellia-player-windows-release` (uploaded from `build/windows/runner/Release/`, retained for 14 days)

## Project layout

```
lib/
  main.dart                 # App entry + theme
  home_screen.dart          # File-picker landing page + drag-drop + last-played card
  player_screen.dart        # Chewie-powered player + subtitle overlay
  subtitle_loader.dart      # SRT parser (also handles VTT/ASS via the `subtitle` package)
  last_played.dart          # JSON-backed "last played" record
windows/
  runner/main.cpp           # Window title + default size
```

## Notes

- The `subtitle` package is used as the primary parser; a robust SRT fallback is included if the file format is unusual.
- Audio/video codec support depends on what Windows Media Foundation supports natively; for H.264/AAC MP4 this works out of the box.
- For full-screen on Windows, click the Chewie fullscreen toggle.
