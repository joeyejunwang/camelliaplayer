# Camellia Player

A simple, modern Flutter **video player** for **Windows desktop** (and Web).
Pick a local video file, optionally attach an SRT/VTT subtitle file, and play.

## Features

- Pick any local video file (mp4, mkv, webm, mov, …)
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
# Windows desktop
flutter run -d windows

# Or, in Chrome while you set up Visual Studio
flutter run -d chrome
```

## Build a release executable

```bash
flutter build windows --release
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
  home/
    home_screen.dart        # File-picker landing page
  player/
    player_screen.dart      # Chewie-powered player + subtitle overlay
  subtitles/
    subtitle_loader.dart    # SRT parser (also handles VTT/ASS via the `subtitle` package)
windows/
  runner/main.cpp           # Window title + default size
```

## Notes

- The `subtitle` package is used as the primary parser; a robust SRT fallback is included if the file format is unusual.
- Audio/video codec support depends on what Windows Media Foundation supports natively; for H.264/AAC MP4 this works out of the box.
- For full-screen on Windows, click the Chewie fullscreen toggle.
