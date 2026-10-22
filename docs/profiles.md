# Playback profiles

`[default]` includes only `MPV_COMMON`. The common profile defines shared title, playlist, subtitle, window and resume preferences. No global fullscreen override is needed.

| Profile | Applied when | Purpose |
| --- | --- | --- |
| `MPV_COMMON` | Configuration startup | Shared preferences; video position saving enabled |
| `AUTO_MUSIC` | Lua confirms audio without real video | Custom panel, windowed playback, native resizing, no color-space hint |
| `AUDIO_PLAYBACK` | Each audio file loads | File-local start/resume/save policy |
| `HDR_OFF` | Real SDR video, excluding selected Dolby Vision profiles | Neutral SDR targets and fullscreen |
| `HDR_ON` | Real PQ or HLG video | Automatic display targets and HDR gamut settings |
| `auto-hdr-generic` | PQ/HLG without scene maxima or selected Dolby Vision profiles | Enable peak computation |
| `auto-dolby-vision-rpu` | Dolby Vision profile 5, 8 or 9 | Disable peak computation |
| `auto-hdr10plus` | Real video exposes nonzero scene maxima | ST 2094-40 tone mapping; disable peak computation |
| `VIDEO_FALLBACK` | Any real video, including silent video | Base video window/fullscreen/controller behavior |
| `protocol.http`, `protocol.https`, `protocol.ytdl` | Matching protocol | Shared stream cache and HLS preferences |

“Real video” excludes still-image and album-art tracks. Scene maxima are the observable condition used for the HDR10+ overlay; this is not a complete metadata validator. Dolby Vision profile selection does not by itself guarantee decoding or output support.

## Lifecycle and precedence

The script applies `AUTO_MUSIC` only when switching into audio mode, and restores it when switching out. It remains active across consecutive audio files. Unknown extensions retain the previous mode until `on_preloaded` can inspect the track list; this prevents a temporary fullscreen change during ambiguous audio loads.

`AUDIO_PLAYBACK` is read from mpv's profile list and applied through `file-local-options`. These options reset for the next file, allowing video resume to remain enabled. Do not add a `profile-cond` to the manually managed music profile.

Automatic profiles use `profile-restore=copy-equal`, restoring only values still equal to their applied values. `VIDEO_FALLBACK` is deliberately declared **after** the HDR profiles: on the tested build, this makes the broad video base evaluate before the specialized overlays. Reordering can cause restoration from one profile to overwrite another profile's fullscreen state. Keep this order and rerun the runtime suite after profile changes.

Command-line options, other scripts and separately loaded configuration can affect the result. Test custom combinations explicitly.

## Rendering scope

Targets such as transfer function, primaries, peak luminance and contrast stay automatic. The HDR profile does not encode a particular display's brightness, gamut or contrast. The panel disables color-space hints during audio playback so album art does not request an output color-space change.

The runtime suite checks SDR, unknown-extension video, PQ, HLG and audio transitions with null audio/video outputs. Physical fullscreen, Windows Snap, actual HDR output and metadata-specific Dolby Vision/HDR10+ playback require manual verification with suitable hardware and media.
