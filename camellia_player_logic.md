# Camellia Player — application logic

This document maps the current code in `lib/` and the Windows runner. Windows and macOS use the desktop path; iOS uses a separate player. The diagrams show implemented behavior, including error and fallback paths. Visual layout and color constants are omitted because they do not change the control flow.

## 1. App startup and platform choice

```mermaid
flowchart TD
    A["Launch app"] --> B["Initialize Flutter bindings"]
    B --> C{"Windows or macOS?"}
    C -- Yes --> D["Initialize MediaKit"]
    D --> E["Initialize window manager and desktop window"]
    E --> F{"Window setup succeeds?"}
    F -- Yes --> G["Show and focus window"]
    F -- No --> H["Log error and continue"]
    C -- No --> I["Run Flutter app"]
    G --> I
    H --> I
    I --> J{"iOS?"}
    J -- Yes --> K["Cupertino app → iOS home"]
    J -- No --> L["Material app → desktop home"]
```

On Windows, the native runner creates the Flutter window, registers plugins, shows the first frame, and processes Windows messages. Flutter then applies the custom window title bar and the dark theme. Source: `windows/runner/main.cpp`, `windows/runner/flutter_window.cpp`, `lib/main.dart`.

## 2. Desktop: choose a file and begin playback

```mermaid
flowchart TD
    A["Desktop home"] --> B["Read last_played.json"]
    B --> C{"Saved media file still exists?"}
    C -- No --> D["Clear stale record"]
    C -- Yes --> E["Show Last played card"]
    D --> F["Wait for user action"]
    E --> F
    F --> G{"Open how?"}
    G -- Browse --> H["Pick supported audio or video file"]
    G -- Drop --> I["Use first supported dropped media file"]
    G -- Last played --> J["Use saved path and lyric index"]
    H --> K["Check media exists"]
    I --> K
    J --> K
    K -- No --> L["Show file-not-found message"]
    K -- Yes --> M["Find companion subtitle"]
    M --> N["Exact media basename + srt, vtt, ass, or ssa"]
    N --> O{"Found?"}
    O -- No --> P["Try same stem with suffix; otherwise sole subtitle in folder"]
    O -- Yes --> Q["Pass optional subtitle file"]
    P --> Q
    Q --> R{"Fresh open?"}
    R -- Yes --> S["Save last-played path and name"]
    R -- Resume --> T["Keep saved lyric index"]
    S --> U["Navigate to desktop PlayerScreen"]
    T --> U
    U --> V["Create VideoController around shared MediaKit Player"]
    V --> W["Open media paused; clear previous lyric state"]
    W --> X["Load and parse supplied subtitle"]
    X --> Y{"Usable cues loaded?"}
    Y -- No --> Z["Search the media folder again and try a companion subtitle"]
    Y -- Yes --> AA["Choose saved cue, or cue 1 for a fresh open"]
    Z --> AB{"Usable cues now?"}
    AB -- Yes --> AA
    AB -- No --> AC{"Resume requested or subtitle file found?"}
    AC -- Yes --> AD["Stay paused; show lyric-load message"]
    AC -- No --> AE["Play from media start"]
    AA --> AF["Wait until media duration is known"]
    AF --> AG["Seek to selected cue start; verify position; retry once if needed"]
    AG --> AH{"Seek succeeded?"}
    AH -- Yes --> AI["Start playback at selected lyric"]
    AH -- No --> AJ["Stay paused; show seek message"]
```

The desktop picker accepts MP3, AAC, WAV, MP4, M4V, MKV, WebM, MOV, AVI, and WMV. The drop target ignores unsupported files. Source: `lib/home_screen.dart`, `lib/player_screen.dart`, `lib/playback_manager.dart`.

## 3. Shared subtitle loading

```mermaid
flowchart TD
    A["Read subtitle file as text"] --> B["Choose format from extension or content"]
    B --> C{"Format"}
    C -- SRT or VTT --> D["Split timed-text blocks"]
    D --> E["Parse start and end timestamps; keep cue text"]
    C -- ASS or SSA --> F["Read Events format and Dialogue rows"]
    F --> G["Remove style tags and convert line breaks"]
    C -- TTML or other supported type --> H["Use subtitle package parser"]
    H --> I{"Package parser succeeds?"}
    I -- No --> J["Try SRT-style parser"]
    I -- Yes --> K["Convert parsed cues"]
    E --> L["Discard empty text and placeholder underscores"]
    G --> L
    J --> L
    K --> L
    L --> M["List of start, end, text entries"]
    M --> N["Player screen stores entries; desktop also gives them to PlaybackManager"]
```

SRT and VTT fractions are normalized to milliseconds. Cue text is active from its start until just before its end. Source: `lib/subtitle_loader.dart`.

## 4. Desktop: position updates and repeat modes

```mermaid
flowchart TD
    A["MediaKit position event"] --> B["Update position and notify UI"]
    B --> C{"Automatic seek pending?"}
    C -- Yes --> D{"Position reached seek target?"}
    D -- Yes --> E["Clear pending seek; skip repeat decision for this tick"]
    D -- No --> F["Ignore old position tick"]
    C -- No --> G{"Repeat mode = forever?"}
    G -- Yes --> H{"At or past selected lyric loop end?"}
    H -- Yes --> I["Seek back to selected lyric start"]
    H -- No --> J["Continue current lyric"]
    G -- No --> K{"Playing with loaded lyrics?"}
    K -- No --> L["No automatic lyric action"]
    K -- Yes --> M["Use anchored lyric index; infer it once if absent"]
    M --> N{"Before anchored lyric start?"}
    N -- Yes --> O["Wait for lyric start"]
    N -- No --> P{"At or past lyric end?"}
    P -- No --> J
    P -- Yes --> Q["Increment completed plays for this lyric"]
    Q --> R{"Count below ×1, ×2, or ×3 target?"}
    R -- Yes --> S["Seek to same lyric start; keep anchor and count"]
    R -- No --> T["Reset count; anchor next lyric, wrapping after last"]
    T --> U["Seek to next lyric start"]
```

```mermaid
flowchart TD
    A["Select ×1, ×2, ×3, or ∞"] --> B["Find anchored/current lyric; use first if before all cues"]
    B --> C["Set mode and reset play count"]
    C --> D["Set loop bounds for that lyric"]
    D --> E["Seek immediately to lyric start"]
    E --> F["Play from that lyric under new mode"]
    G["Manual seek or lyric navigation"] --> H["Reset count and cancel older automatic seek"]
    H --> I["Anchor cue at requested position"]
    I --> J["Seek to requested position"]
    K["MediaKit completed event"] --> L{"completed = true?"}
    L -- No --> M["Ignore status reset from open or seek"]
    L -- Yes --> N{"Mode = ∞?"}
    N -- Yes --> O["Seek to loop start and resume"]
    N -- No --> P["Reset displayed position and repeat count"]
```

×1 plays the selected lyric once and advances; ×2 and ×3 play it two or three times; ∞ repeats the selected lyric. Choosing a mode again restarts the current lyric. Automatic repeat and mode-change seeks use revision checks so an older request cannot restart playback after a newer one. Source: `lib/playback_manager.dart`.

## 5. Desktop controls, recording, and exit

```mermaid
flowchart TD
    A["Desktop player UI"] --> B{"User action"}
    B -- Space or play button --> C["Play/pause"]
    B -- Home or End --> D["First or last lyric"]
    B -- Left or Right --> E["Previous or next lyric"]
    B -- Lyric row or ruler --> F["Seek to chosen lyric"]
    B -- R or repeat menu --> G["Choose repeat mode; restart current lyric"]
    B -- Up/Down or volume slider --> H["Change volume"]
    B -- S --> I["Toggle MediaKit subtitle track"]
    B -- L or lyric button --> J["Toggle lyric panel"]
    B -- V or recorder button --> K{"Already recording?"}
    K -- No --> L["Request microphone permission"]
    L --> M{"Granted?"}
    M -- Yes --> N["Record AAC audio to timestamped m4a file"]
    N --> O["Update amplitude display every 80 ms"]
    M -- No --> A
    K -- Yes --> P["Stop recorder and amplitude timer"]
    B -- Back --> Q["Flush saved lyric cue; pop player route"]
    B -- Window close button --> R["Flush saved lyric cue; close window"]
    Q --> S["PlayerScreen dispose: cancel listener and stop MediaKit"]
```

The video area displays video for video files, or music artwork plus the active lyric for MP3, WAV, and AAC. The mini-player shows progress, transport buttons, repeat selection, subtitle and lyric toggles, a lyric ruler, volume, and voice recording. The title bar also handles minimize, maximize, restore, and dragging. Source: `lib/player_screen.dart`, `lib/mini_player.dart`, `lib/custom_title_bar.dart`.

## 6. iOS: browse, pick, and open media

```mermaid
flowchart TD
    A["iOS home"] --> B["Read saved last-played record"]
    A --> C["List Documents folder"]
    C --> D["Show non-hidden folders and supported media, sorted folders first"]
    D --> E{"User action"}
    E -- Open folder or Back --> F["Update directory stack; reload list"]
    E -- Tap media --> G["Open selected media"]
    E -- Last played --> H["Open saved media and saved lyric index"]
    E -- Files picker --> I["Pick at most one media and one subtitle file"]
    I --> J{"Valid types and matching basenames?"}
    J -- No --> K["Show selection error"]
    J -- Yes --> G
    G --> L["Check media exists"]
    H --> L
    L -- No --> M["Show file-not-found error"]
    L -- Yes --> N["Use explicit subtitle, or exact-basename sibling"]
    N --> O["Write last-played path, name, and optional cue index"]
    O --> P["Push iOS player screen"]
    P --> Q["Initialize VideoPlayerController for local file"]
    Q --> V{"Initialization succeeds?"}
    V -- No --> W["Show player error view"]
    V -- Yes --> R{"Subtitle available?"}
    R -- Yes --> S["Load subtitle cues"]
    R -- No --> T["Keep starting position"]
    S --> X{"Subtitle load succeeds?"}
    X -- No --> W
    X -- Yes --> Y{"Usable cues found?"}
    Y -- Yes --> Z["Clamp saved index; seek to cue start; save cue index"]
    Y -- No --> U["Show player and start playback"]
    Z --> U
    T --> U
```

The iOS picker supports MP3, WAV, AAC, MP4, M4V, MKV, WebM, MOV, and AVI. Users can also add or replace a subtitle file while the player is open; a readable file resets repeat mode to ∞ and seeks to the saved or first cue. Source: `lib/ios_home_screen.dart`, `lib/ios_player_screen.dart`.

## 7. iOS: playback, lyrics, and controls

```mermaid
flowchart TD
    A["VideoPlayerController notification"] --> B["Read current position and lyric"]
    B --> C{"Automatic seek pending?"}
    C -- Yes --> D["Wait for seek to finish"]
    C -- No --> E{"Repeat mode = ∞?"}
    E -- Yes --> F["Use selected loop lyric or timeline lyric"]
    F --> G{"Reached next cue start, cue end, or media completion?"}
    G -- Yes --> H["Seek to loop lyric start and resume"]
    G -- No --> I["Continue playback"]
    E -- No --> J{"Playing and at current cue end?"}
    J -- No --> I
    J -- Yes --> K["Increment ×1, ×2, or ×3 count"]
    K --> L{"More plays required?"}
    L -- Yes --> M["Seek to same cue start and resume"]
    L -- No --> N["Reset count; seek to next cue, wrapping after last"]
    B --> O["Persist changed lyric index"]
    B --> P["Refresh lyric overlay, list, and progress ruler"]
    Q["iOS controls"] --> R["Tap video to play/pause; first, previous, next, last, row, or ruler to seek"]
    Q --> S["Choose repeat mode; toggle overlay or lyric list"]
    Q --> T["Set volume or toggle mute; pick a new subtitle"]
    Q --> U["Back: pop route and dispose video controller"]
```

The iOS player uses `video_player`, not the desktop `PlaybackManager`. Its repeat choice resets the count and loop anchor; unlike the Windows control, it does not explicitly restart the cue when the mode is selected. Source: `lib/ios_player_screen.dart`.

## 8. Shared last-played storage

```mermaid
flowchart TD
    A["Home opens new media"] --> B["Write media path and display name"]
    C["Player reaches or selects a different lyric"] --> D["Queue updated lyric index"]
    D --> E["Serialize writes to last_played.json in app-support directory"]
    B --> E
    F["Home opens Last played"] --> G["Read JSON record"]
    G --> H{"Media path exists?"}
    H -- No --> I["Delete stale JSON record"]
    H -- Yes --> J["Pass saved zero-based lyric index to player"]
    J --> K["Clamp index to loaded cue range, then seek"]
    L["Desktop back or title-bar close"] --> M["Queue current lyric and await saved writes"]
    M --> E
```

The stored lyric index is zero-based; the UI displays it as lyric number `index + 1`. Storage errors are treated as best-effort and do not stop playback. Source: `lib/last_played.dart`, `lib/home_screen.dart`, `lib/player_screen.dart`, `lib/ios_home_screen.dart`, `lib/ios_player_screen.dart`.
