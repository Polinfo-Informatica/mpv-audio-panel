# MPV Audio Panel

A compact music interface for **mpv**, with a smooth playlist, precise playback controls and automatic video profiles.

![MPV Audio Panel preview](docs/preview.png)

**[Install](#installation) · [Controls](#controls) · [Profiles](docs/profiles.md) · [Restore](#restore-or-uninstall) · [Contributing](CONTRIBUTING.md)**

## Features

- Persistent audio panel with smooth scrolling and a clean, unnumbered playlist.
- Current track title above the progress bar; centered timing and matching volume labels.
- Vector speaker icons with sound waves or a mute cross, plus a subtle monochrome mpv logo.
- Native Windows resizing and Snap support while keeping the custom header.
- Current media title in the window and taskbar.
- Audio starts from the beginning; video keeps mpv's resume behavior.
- Video fullscreen lives in profiles, including a fallback for silent or unclassified video.
- Separate SDR, PQ/HLG, Dolby Vision and HDR10+ profile conditions.
- Installation with checksums, automatic backups and a restore command.

The Lua panel uses only mpv's built-in modules. No additional UI framework, font download or runtime service is required.

## Requirements

- A recent [mpv](https://mpv.io/installation/) build. The package was tested on Windows 11 with **mpv 0.41.0-1205-g01e2533f3**.
- Windows PowerShell 5.1 or PowerShell 7 for the optional installer.
- A build that supports `title-bar`, `auto-window-resize`, `autocreate-playlist`, `profile-restore=copy-equal` and the included color-management options. Older builds may reject these options; check `mpv --list-options`.

Windows is the tested platform. The Lua script can be installed manually elsewhere, but window decoration, dragging, font fallback and HDR behavior depend on the platform and build. Native Snap behavior also depends on Windows settings. The panel requests Segoe UI and uses mpv's normal font fallback when unavailable.

## Installation

### Windows: complete configuration

1. Install mpv separately and close all running mpv windows.
2. Download this repository through **Code → Download ZIP**, then extract it.
3. Open PowerShell in the extracted folder and run:

   ```powershell
   .\Install.ps1
   ```

   `Install.cmd` runs the same installer when local script execution is permitted.

4. Open an audio file with mpv. The panel appears automatically. Videos use the video profiles.

The default destination is `%APPDATA%\mpv`. The installer **replaces `mpv.conf` and `scripts/audio-panel.lua`**, after backing up both. It preserves other files and scripts. Other controller scripts can still conflict with the panel; disable them separately if necessary. Administrator privileges are not needed for a normal per-user installation.

If Windows marks the downloaded files as blocked, inspect them first and use the file Properties **Unblock** option. If local policy prevents PowerShell scripts, use the manual installation below.

### Portable mpv

If `portable_config` exists next to the mpv executable, mpv uses it instead of the usual per-user configuration. Point the installer at that directory:

```powershell
.\Install.ps1 -ConfigDirectory 'D:\Apps\mpv\portable_config'
```

Replace the example with the actual portable configuration directory. Install into the directory mpv actually loads; avoid keeping conflicting copies in multiple locations.

### Manual installation and existing setups

Back up the existing configuration first. Copy the **contents** of `config/` into the mpv configuration directory, preserving the `scripts/` subfolder:

```text
mpv.conf
scripts/
    audio-panel.lua
```

Typical locations are `%APPDATA%\mpv` on Windows and `~/.config/mpv` on Linux. Refer to the [mpv manual](https://mpv.io/manual/master/#files) for platform-specific search paths.

For an existing customized setup, merge the profiles and common settings from `config/mpv.conf`, then add `audio-panel.lua`. The panel requires the exact profile names `AUTO_MUSIC` and `AUDIO_PLAYBACK`. Keep `VIDEO_FALLBACK` after the HDR profiles, as explained in [Profiles](docs/profiles.md). Manual merges are not managed by the installer backup system.

## Controls

| Area | Action |
| --- | --- |
| Playlist row | Play that entry |
| Playlist wheel | Scroll the list |
| Playlist scrollbar | Drag to scroll |
| Previous / play / next | Change track or pause/resume |
| Progress bar | Click or drag to seek |
| Speaker | Toggle mute |
| Volume bar | Click or drag to adjust volume |
| Header | Drag the native window |
| Header minimize / close | Minimize or quit mpv |

Normal mpv keyboard bindings remain available. The panel overrides mouse bindings while audio mode is active. Double-clicking the audio panel does not toggle fullscreen.

At narrow widths, timing text and the logo may be hidden to preserve usable controls. The intended starting size is 840 × 380.

## Customization

Create `script-opts/audio-panel.conf` in the mpv configuration directory:

```ini
scale=1.0
font_size=24
row_height=34
smoothness=18
```

| Option | Purpose |
| --- | --- |
| `scale` | Overall interface scale; values below 0.5 are clamped |
| `font_size` | Playlist, title and numeric label size |
| `row_height` | Playlist row height; increase alongside larger text |
| `smoothness` | Scroll interpolation speed; higher values settle faster |

The global default only bootstraps `MPV_COMMON`. Playback differences live in profiles. Edit `AUDIO_PLAYBACK` to change audio resume policy, `AUTO_MUSIC` for the panel window and the video profiles for fullscreen or rendering preferences. See [Profiles](docs/profiles.md) for conditions and precedence.

Display targets, audio output and language selection use generic or system defaults. HDR profiles select rendering options; they do not enable Windows HDR, calibrate a display or guarantee passthrough on every system.

## Restore or uninstall

Close mpv and run from the extracted package:

```powershell
.\Restore.ps1
```

For portable installations, pass the same `-ConfigDirectory` used during installation. By default, restore selects the latest backup. To choose an earlier installation, use the backup folder name printed by the installer:

```powershell
.\Restore.ps1 -ConfigDirectory 'D:\Apps\mpv\portable_config' -BackupName '<backup-folder-name>'
```

Backups are retained under `mpv-audio-panel-backups/` in the target directory. Each backup contains a manifest and any original managed files. Restore verifies their hashes before applying them. Files absent before installation are removed; existing files are restored byte for byte. **Restoring replaces later edits to these two managed files.** Other files are preserved.

For manual rollback, copy backed-up `mpv.conf` and `scripts/audio-panel.lua` to their original locations. If the manifest says a file did not exist before installation, remove only that installed file. A manual installation can be undone by restoring the separately saved configuration and removing the added panel script.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Panel does not appear | Confirm the active config directory and both required profiles; run `mpv --log-file=mpv.log <audio-file>` and inspect script errors |
| Unknown option error | Update mpv or adapt the unsupported option for the installed build |
| Two controllers appear | Check for another OSC/controller script; the package disables only mpv's built-in OSC in audio mode |
| Video does not enter fullscreen | Check profile order and conflicting configuration or command-line overrides |
| Window flickers on track change | Test with this configuration alone; driver, display-mode and other script behavior can also affect transitions |
| HDR looks incorrect | Confirm OS/display HDR settings and mpv renderer support; keep automatic targets until the display is calibrated |
| Text clips after customization | Increase row height, reduce font size or restore the default scale and window size |

Audio with cover art stays in audio mode. Still images do not activate video fullscreen. File extensions are used only for an early positive audio match; actual tracks decide the final mode. The panel stays active between consecutive audio files to avoid unnecessary window-mode changes.

## Validation and development

See [CONTRIBUTING.md](CONTRIBUTING.md) for reproducible check commands. CI runs StyLua, Selene, PSScriptAnalyzer, package integrity checks and installer/restore tests on Windows. The optional runtime suite uses a real mpv process and synthetic media to exercise audio/video transitions; FFmpeg adds PQ/HLG cases. It does not verify physical HDR output, Dolby Vision metadata or monitor behavior.

## License

[GPL-2.0-or-later](LICENSE). Upstream artwork attribution is in [NOTICE](NOTICE). mpv itself is distributed separately under its upstream terms. This is an independent configuration package, not an official mpv release.
