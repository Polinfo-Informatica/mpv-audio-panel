# Optional video profiles

This package targets Windows and is tested on Windows 11. The project's main feature is the dark, minimalist, monochrome audio interface. Video profiles are an independent extra for systems capable of handling the intended content. Audio mode installs no video profiles or video safety script and adds no video rendering work.

## Components and activation

`mpv.conf` contains only the selected component includes. Audio preferences live in `mpv-audio-panel/audio.conf`; video preferences live in `mpv-audio-panel/video.conf`. Outside their playback mode, profiles restore unchanged values with `profile-restore=copy-equal`.

The audio script manages `AUTO_MUSIC` across genuine mode changes. `AUDIO_PLAYBACK` is applied through file-local options, so audio resume settings do not become video settings. Audio-only installation leaves video defaults or unrelated pre-existing configuration in control.

The video safety script publishes boolean decisions under `user-data/video-safety`. It inspects actual decoded/filter-output parameters and the active output, rather than file names, GPU brands or advertised format labels. Without this script, the optional video profiles remain inactive.

| Profile | Required evidence | Behavior |
| --- | --- | --- |
| `VIDEO_FALLBACK` | Selected real video and valid decoded dimensions | Base window/fullscreen behavior; automatic targets; no forced GPU or decoder |
| `HDR_OFF` | Configured `gpu`/`gpu-next`, a known target and SDR filter output | Automatic SDR processing |
| `HDR_ON` | HDR filter output, configured `gpu-next`, reporting context, automatic strict target negotiation and PQ/HLG/scRGB target | Identifies confirmed HDR rendering output; does not force it |
| `HDR_TONEMAP` | HDR filter output on `gpu`/`gpu-next`, HDR output not confirmed | Automatic compatibility conversion |
| `auto-hdr-generic` | Supported renderer, HDR signal, no active specialized metadata path and no low-power reduction | Automatic peak computation, never forced on |
| `HDR10PLUS_TONEMAP` | `gpu-next`, PQ signal, actual target and complete finite scene maxima in range | Internal ST 2094-40 tone mapping; no native HDR10+ output claim |
| `DOLBY_VISION_TONEMAP` | `gpu-next`, actual target and decoded `dolbyvision` color representation | Internal processing with automatic tone mapping and peak policy |
| `VIDEO_LOW_POWER` | Sustained playback frame drops after a grace period | Disable optional peak computation, contrast recovery, debanding and interpolation for the track |

Still images and album art never activate video profiles. Undecoded or failed streams do not qualify as real video. Unsupported renderers receive only the base window behavior; no specialized color-processing profile is selected.

## Output capability checks

Confirmed HDR requires `target-colorspace-hint=auto`, `target-colorspace-hint-mode=target`, strict negotiated-output handling and an HDR transfer function in `video-target-params`. The reporting contexts currently recognized are D3D11, Windows Vulkan and Wayland OpenGL/Vulkan. An unknown context is not treated as proof of HDR support; it remains on the compatibility path without blocking playback.

Target primaries, transfer, peak brightness, gamut and contrast remain automatic. No GPU model, codec whitelist, fixed luminance, forced decoder or synthetic hardware benchmark is used. Software decoding remains valid when it can keep up. Moving the window or changing the output causes the decision to be reevaluated.

These checks describe what mpv actually negotiates, not a physical certification of the entire display chain. A driver can report incorrect capabilities. Native HDR10+/Dolby Vision signaling is not guaranteed or enabled by these profiles, and OS HDR is never toggled by the package.

## Dynamic metadata and compatibility

HDR10+ scene maxima must include all RGB components, be finite, lie between 0 and 10000 nits and contain at least one positive value. Once observed, support is retained for black scenes in the same file/track; a new file or selected track clears that evidence. The renderer's documented ST 2094-40 fallback handles missing per-scene metadata. A Dolby Vision representation takes precedence over HDR10+ classification.

Container Dolby Vision profile numbers alone are insufficient: a tag does not establish that RPU data reached the renderer. The decoded color representation supplies stronger evidence. This does not validate every Dolby Vision enhancement-layer path or guarantee decoder compatibility; unsupported streams still need an appropriate decoder/build.

Internal metadata-based tone mapping can validly target SDR or HDR10. Requiring an HDR10+-certified display for SDR conversion would reject working systems unnecessarily. Conversely, an HDR source alone never qualifies as confirmed HDR output.

## Performance behavior

Optional contrast recovery is disabled and histogram percentile refinement is not added by default. Peak detection uses mpv's `auto` capability checks. Rendering and decoder drop counters are sampled once per second. Reduction requires three consecutive qualifying intervals with at least three drops and roughly 10% of the nominal frame rate lost per interval.

Startup, seeking, cache pauses, paused playback, position jumps and altered playback speed receive exclusions or a new grace period. Low-power reduction is latched for the current track to avoid oscillation and resets with the file/selected track. It does not change resolution, output transfer function, OS HDR or the audio UI. It cannot guarantee smooth playback on hardware unable to decode the source.

## Precedence and manual verification

Keep `VIDEO_FALLBACK` last among the conditional video profiles: on the tested mpv build, the broad base is evaluated before the specialized overlays. Keep `VIDEO_LOW_POWER` first so its reduction is applied last. Other configuration, scripts and command-line options can change the result; test custom combinations explicitly.

The automated suite covers simulated supported, unsupported and incomplete capability reports; valid/malformed metadata; cover exclusion; sustained drops; and 24 real-mpv audio/video transitions across the three modes. Null outputs and synthetic PQ/HLG media cannot verify a real monitor, GPU driver, Dolby Vision enhancement layer or physical HDR signal. Verify those manually with suitable hardware and media.

## Upstream references

- [mpv properties](https://mpv.io/manual/master/#properties): `video-out-params`, `video-target-params`, `current-vo`, `current-gpu-context`, frame-drop counters.
- [mpv video options](https://mpv.io/manual/master/#video): automatic peak computation, tone mapping and negotiated color-space hints.
- [Upstream format-detection guidance](https://github.com/mpv-player/mpv/discussions/14024): decoded Dolby Vision representation and HDR10+ scene maxima.
