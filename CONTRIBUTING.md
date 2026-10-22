# Contributing

Keep interface changes focused, preserve audio/video mode boundaries and use English for source comments, messages and documentation. Do not commit media collections, personal configuration, absolute workstation paths, logs or backups.

## Static checks and installation tests

On Windows, run from the repository root:

```powershell
.\scripts\Get-CheckTools.ps1
.\scripts\Invoke-Checks.ps1
```

The bootstrap downloads official, pinned releases of StyLua 2.6.0, Selene 0.32.0 and PSScriptAnalyzer 1.25.0 into ignored `.tools/`, verifying SHA-256 before extraction. No global tool installation is required. CI uses the same commands. Python syntax is also checked in CI.

Format Lua with:

```powershell
.\.tools\stylua\stylua.exe config/scripts tests
```

After editing any distributed file under config/, refresh `checksums.json`:

```powershell
$hashes = [ordered]@{}
foreach ($path in @('mpv.conf', 'scripts/audio-panel.lua', 'scripts/video-safety.lua', 'mpv-audio-panel/audio.conf', 'mpv-audio-panel/video.conf')) {
    $hashes[$path] = (Get-FileHash (Join-Path ./config $path) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$hashes | ConvertTo-Json | Set-Content ./checksums.json -Encoding ascii
```

Installer tests use isolated directories under ignored `test-output/`. They cover fresh installation, byte-exact restoration, unrelated-file preservation and rejection of modified package contents. All three modes, mode switching, preservation of unrelated configuration and legacy backup restoration are covered. Existing mpv configuration is not used by the tests.

## Runtime regression tests

With Python 3.9+ and a recent mpv executable:

```powershell
python tests/runtime.py --mpv 'D:\Apps\mpv\mpv.exe'
```

If mpv is on PATH, omit `--mpv`. No Python packages are required. FFmpeg on PATH adds synthetic PQ and HLG fixtures and requires its `libx264` encoder. Without FFmpeg those cases are explicitly skipped. Fixtures and watch-later data stay in an isolated test directory and are removed after the run.

The suite checks Audio, Video and Both modes, including window mode, controller selection, per-file resume/save policy and the absence of a fullscreen request between ordinary and ambiguous-extension audio. It also exercises synthetic output capability, metadata and sustained-drop decisions. It also checks HDR peak profile selection when fixtures are available. Outputs are null, so physical display behavior is outside the test's scope.

Before submitting UI changes, manually inspect narrow and default window sizes, muted/unmuted icons, volume and timing alignment, long playlist titles, scrolling, seeking, native dragging and Windows Snap. Before changing video profiles, verify real SDR/HDR media and audio/video transitions.

## Licensing

Contributions are distributed under GPL-2.0-or-later. Preserve SPDX identifiers and upstream attribution in NOTICE. Do not include the mpv executable or third-party media in the repository.
