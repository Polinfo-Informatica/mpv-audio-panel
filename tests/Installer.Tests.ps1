# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot
$testRoot = Join-Path $project 'test-output'
$sandbox = Join-Path $testRoot ('installer-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sandbox
function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
$fresh = Join-Path $sandbox 'fresh'
& (Join-Path $project 'Install.ps1') -ConfigDirectory $fresh | Out-Null
Assert-Condition (Test-Path (Join-Path $fresh 'scripts/audio-panel.lua')) 'Fresh install failed'
& (Join-Path $project 'Restore.ps1') -ConfigDirectory $fresh | Out-Null
Assert-Condition (-not (Test-Path (Join-Path $fresh 'mpv.conf'))) 'Restore retained a newly installed config'
Assert-Condition (-not (Test-Path (Join-Path $fresh 'scripts/audio-panel.lua'))) 'Restore retained a newly installed script'
$existing = Join-Path $sandbox 'existing'
$null = New-Item -ItemType Directory -Path (Join-Path $existing 'scripts') -Force
Set-Content (Join-Path $existing 'mpv.conf') 'original configuration'
Set-Content (Join-Path $existing 'scripts/audio-panel.lua') 'original script'
Set-Content (Join-Path $existing 'scripts/unrelated.lua') 'unrelated script'
$before = (Get-FileHash (Join-Path $existing 'mpv.conf')).Hash
& (Join-Path $project 'Install.ps1') -ConfigDirectory $existing | Out-Null
& (Join-Path $project 'Restore.ps1') -ConfigDirectory $existing | Out-Null
Assert-Condition ((Get-FileHash (Join-Path $existing 'mpv.conf')).Hash -eq $before) 'Existing config was not restored exactly'
Assert-Condition ((Get-Content (Join-Path $existing 'scripts/audio-panel.lua')) -eq 'original script') 'Existing script was not restored'
Assert-Condition ((Get-Content (Join-Path $existing 'scripts/unrelated.lua')) -eq 'unrelated script') 'Unrelated script was modified'
# Repeated installs preserve a chain of explicitly selectable backups.
& (Join-Path $project 'Install.ps1') -ConfigDirectory $existing | Out-Null
$firstBackup = (Get-ChildItem (Join-Path $existing 'mpv-audio-panel-backups') -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).Name
$installedHash = (Get-FileHash (Join-Path $existing 'mpv.conf')).Hash
& (Join-Path $project 'Install.ps1') -ConfigDirectory $existing | Out-Null
& (Join-Path $project 'Restore.ps1') -ConfigDirectory $existing | Out-Null
Assert-Condition ((Get-FileHash (Join-Path $existing 'mpv.conf')).Hash -eq $installedHash) 'Update restore failed'
& (Join-Path $project 'Restore.ps1') -ConfigDirectory $existing -BackupName $firstBackup | Out-Null
Assert-Condition ((Get-FileHash (Join-Path $existing 'mpv.conf')).Hash -eq $before) 'Selected backup restore failed'
# Corrupt backups must be rejected before changing managed files.
Add-Content (Join-Path (Join-Path (Join-Path $existing 'mpv-audio-panel-backups') $firstBackup) 'mpv.conf') '# corrupt'
$restoreRejected = $false
try { & (Join-Path $project 'Restore.ps1') -ConfigDirectory $existing -BackupName $firstBackup | Out-Null } catch { $restoreRejected = $true }
Assert-Condition $restoreRejected 'Corrupt backup was accepted'
Assert-Condition ((Get-FileHash (Join-Path $existing 'mpv.conf')).Hash -eq $before) 'Rejected backup changed the destination'
# A corrupt package must fail before writing to the destination.
$package = Join-Path $sandbox 'package'
$null = New-Item -ItemType Directory -Path $package
foreach ($item in @('Install.ps1', 'Restore.ps1', 'checksums.json', 'config')) {
    Copy-Item -LiteralPath (Join-Path $project $item) -Destination $package -Recurse
}
Add-Content (Join-Path $package 'config/mpv.conf') '# corrupt'
$rejected = $false
try { & (Join-Path $package 'Install.ps1') -ConfigDirectory (Join-Path $sandbox 'rejected') | Out-Null } catch { $rejected = $true }
Assert-Condition $rejected 'Corrupt package was accepted'
Assert-Condition (-not (Test-Path (Join-Path $sandbox 'rejected'))) 'Rejected package changed the destination'
Write-Output 'Installer checks passed: fresh install, exact restore, updates, unrelated files, corrupt package and backup rejection.'
foreach ($mode in @('Audio', 'Video', 'Both')) {
    $target = Join-Path $sandbox $mode
    $null = New-Item -ItemType Directory -Path $target
    $sentinel = "# Existing preferences`nvolume=41`n[external-profile]`nsub-scale=1.2`n"
    [IO.File]::WriteAllText((Join-Path $target 'mpv.conf'), $sentinel)
    & (Join-Path $project 'Install.ps1') -ConfigDirectory $target -Mode $mode | Out-Null
    $installed = Get-Content (Join-Path $target 'mpv.conf') -Raw
    Assert-Condition ($installed.Contains($sentinel.TrimEnd())) "$mode changed unrelated configuration"
    Assert-Condition ((Test-Path (Join-Path $target 'scripts/audio-panel.lua')) -eq ($mode -ne 'Video')) "$mode audio isolation failed"
    Assert-Condition ((Test-Path (Join-Path $target 'scripts/video-safety.lua')) -eq ($mode -ne 'Audio')) "$mode video isolation failed"
    Assert-Condition ($installed.Contains('include=~~/mpv-audio-panel/audio.conf') -eq ($mode -ne 'Video')) "$mode audio include failed"
    Assert-Condition ($installed.Contains('include=~~/mpv-audio-panel/video.conf') -eq ($mode -ne 'Audio')) "$mode video include failed"
    & (Join-Path $project 'Install.ps1') -ConfigDirectory $target -Mode Video | Out-Null
    & (Join-Path $project 'Install.ps1') -ConfigDirectory $target -Mode Audio | Out-Null
    Assert-Condition (-not (Test-Path (Join-Path $target 'scripts/video-safety.lua'))) 'Mode switch retained video processing'
    Assert-Condition (([regex]::Matches((Get-Content (Join-Path $target 'mpv.conf') -Raw), '# BEGIN MPV AUDIO PANEL')).Count -eq 1) 'Mode switch duplicated the loader'
    & (Join-Path $project 'Restore.ps1') -ConfigDirectory $target | Out-Null
    Assert-Condition (Test-Path (Join-Path $target 'scripts/video-safety.lua')) 'Mode-switch rollback lost video component'
    Assert-Condition (-not (Test-Path (Join-Path $target 'scripts/audio-panel.lua'))) 'Mode-switch rollback retained audio component'
}
# Version 1 backups from the original two-file package remain restorable.
$legacy = Join-Path $sandbox 'legacy'
& (Join-Path $project 'Install.ps1') -ConfigDirectory $legacy | Out-Null
$legacyBackup = Get-ChildItem (Join-Path $legacy 'mpv-audio-panel-backups') -Directory | Select-Object -First 1
$legacyManifest = Join-Path $legacyBackup.FullName 'manifest.json'
$record = Get-Content $legacyManifest -Raw | ConvertFrom-Json
$record.Version = 1
$record.Files = @($record.Files | Where-Object {$_.Path -in @('mpv.conf', 'scripts/audio-panel.lua')})
$record | ConvertTo-Json -Depth 4 | Set-Content $legacyManifest -Encoding UTF8
& (Join-Path $project 'Restore.ps1') -ConfigDirectory $legacy | Out-Null
Assert-Condition (-not (Test-Path (Join-Path $legacy 'mpv.conf'))) 'Legacy backup restore failed'
Write-Output 'Component checks passed: Audio, Video, Both, mode switching, config preservation and legacy backups.'

# Inject menu input without replacing native cmdlets or relying on console redirection.
$menuTarget = Join-Path $sandbox 'menu'
$menuChoices = [Collections.Generic.Queue[string]]::new()
$readMenu = {
    if ($menuChoices.Count -eq 0) { throw 'Unexpected menu prompt.' }
    $menuChoices.Dequeue()
}.GetNewClosure()
foreach ($choice in @('invalid', '3')) { $menuChoices.Enqueue($choice) }
& (Join-Path $project 'Install.ps1') -ConfigDirectory $menuTarget -Menu -MenuReader $readMenu | Out-Null
Assert-Condition (Test-Path (Join-Path $menuTarget 'scripts/audio-panel.lua')) 'Menu Both lost audio'
Assert-Condition (Test-Path (Join-Path $menuTarget 'scripts/video-safety.lua')) 'Menu Both lost video'
$menuChoices.Enqueue('4')
& (Join-Path $project 'Install.ps1') -ConfigDirectory $menuTarget -Menu -MenuReader $readMenu | Out-Null
Assert-Condition (-not (Test-Path (Join-Path $menuTarget 'mpv.conf'))) 'Menu restore failed'
$menuChoices.Enqueue('0')
& (Join-Path $project 'Install.ps1') -ConfigDirectory $menuTarget -Menu -MenuReader $readMenu | Out-Null
Assert-Condition (-not (Test-Path (Join-Path $menuTarget 'mpv.conf'))) 'Menu cancel changed configuration'
foreach ($choice in @('1', '2')) {
    $menuChoices.Enqueue($choice)
    & (Join-Path $project 'Install.ps1') -ConfigDirectory $menuTarget -Menu -MenuReader $readMenu | Out-Null
    Assert-Condition ((Test-Path (Join-Path $menuTarget 'scripts/audio-panel.lua')) -eq ($choice -eq '1')) 'Menu audio selection failed'
    Assert-Condition ((Test-Path (Join-Path $menuTarget 'scripts/video-safety.lua')) -eq ($choice -eq '2')) 'Menu video selection failed'
}
& (Join-Path $project 'Install.ps1') -ConfigDirectory $menuTarget -Menu -Mode Both -MenuReader $readMenu | Out-Null
Assert-Condition ($menuChoices.Count -eq 0) 'Explicit mode unexpectedly prompted'
Write-Output 'Unified menu checks passed: all modes, restore, invalid input, cancel and explicit mode.'

# Run the actual CMD launcher and Windows PowerShell backend, not only the script API.
$launcherTarget = Join-Path $sandbox 'launcher'
$launcherCommand = 'call "{0}" -Mode Both -ConfigDirectory "{1}" < NUL' -f (Join-Path $project 'Install.cmd'), $launcherTarget
$launcherOutput = (& $env:ComSpec /d /c $launcherCommand) -join "`n"
Assert-Condition ($LASTEXITCODE -eq 0) 'CMD launcher installation failed'
Assert-Condition ($launcherOutput.Contains('MPV Audio Panel setup')) 'Launcher startup is not visible'
Assert-Condition ($launcherOutput.Contains('Installation complete: Both')) 'Launcher did not complete installation'
Assert-Condition (Test-Path (Join-Path $launcherTarget 'scripts/audio-panel.lua')) 'Launcher lost audio'
Assert-Condition (Test-Path (Join-Path $launcherTarget 'scripts/video-safety.lua')) 'Launcher lost video'
& (Join-Path $project 'Restore.ps1') -ConfigDirectory $launcherTarget | Out-Null
Assert-Condition (-not (Test-Path (Join-Path $launcherTarget 'mpv.conf'))) 'Launcher install did not restore'
Write-Output 'CMD launcher checks passed: visible startup, Windows PowerShell installation and restore.'


# Migrate old inline project profiles automatically, with an exact original backup.
$legacyNames = @(
    'AUTO_MUSIC', 'AUDIO_PLAYBACK', 'HDR_OFF', 'HDR_ON', 'HDR_TONEMAP',
    'auto-hdr-generic', 'auto-dolby-vision-rpu', 'auto-hdr10plus',
    'DOLBY_VISION_TONEMAP', 'HDR10PLUS_TONEMAP', 'VIDEO_LOW_POWER', 'VIDEO_FALLBACK'
)
foreach ($mode in @('Audio', 'Video', 'Both')) {
    $migrationTarget = Join-Path $sandbox ('migration-' + $mode)
    $null = New-Item -ItemType Directory -Path (Join-Path $migrationTarget 'scripts') -Force
    $globalOptions = "# Personal preferences`r`nprofile=high-quality`r`nalang=por,en`r`nscreen=2`r`n"
    $sharedProfile = "[KAOS_COMMON]`r`nvolume=41`r`n[default]`r`nprofile=KAOS_COMMON`r`n"
    $personalProfile = "[AUTO_MUSIC_EXTRA]`r`nsub-scale=1.2`r`n[fast]`r`nscale=bilinear`r`n"
    $oldConfig = $globalOptions + $sharedProfile
    foreach ($name in $legacyNames) {
        $oldConfig += "  [$name] # Legacy project profile`r`nfullscreen=yes`r`n"
    }
    $oldConfig += "[AUTO_MUSIC]`r`ngeometry=640x160`r`n" + $personalProfile
    $migrationConfig = Join-Path $migrationTarget 'mpv.conf'
    [IO.File]::WriteAllText($migrationConfig, $oldConfig, [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $migrationTarget 'scripts/audio-panel.lua'), 'old audio script')
    [IO.File]::WriteAllText((Join-Path $migrationTarget 'scripts/unrelated.lua'), 'personal script')
    $originalHash = (Get-FileHash -LiteralPath $migrationConfig).Hash
    & (Join-Path $project 'Install.ps1') -ConfigDirectory $migrationTarget -Mode $mode | Out-Null
    $migrated = [IO.File]::ReadAllText($migrationConfig)
    foreach ($section in @($globalOptions, $sharedProfile, $personalProfile)) {
        Assert-Condition ($migrated.Contains($section.TrimEnd())) "$mode migration lost unrelated preferences"
    }
    Assert-Condition (-not ($migrated -match '(?m)^[ \t]*\[(AUTO_MUSIC|HDR_ON|VIDEO_FALLBACK)\]')) "$mode retained inline project profiles"
    Assert-Condition ((Get-Content (Join-Path $migrationTarget 'scripts/unrelated.lua') -Raw) -eq 'personal script') 'Migration changed a personal script'
    $migrationBackup = Get-ChildItem (Join-Path $migrationTarget 'mpv-audio-panel-backups') -Directory | Select-Object -First 1
    $migrationManifest = Get-Content (Join-Path $migrationBackup.FullName 'manifest.json') -Raw | ConvertFrom-Json
    Assert-Condition (@($migrationManifest.MigratedProfiles).Count -eq $legacyNames.Count) 'Migration manifest omitted profiles'
    Assert-Condition ((Get-FileHash (Join-Path $migrationBackup.FullName 'mpv.conf')).Hash -eq $originalHash) 'Migration backup is not byte-exact'
    $migratedHash = (Get-FileHash -LiteralPath $migrationConfig).Hash
    & (Join-Path $project 'Install.ps1') -ConfigDirectory $migrationTarget -Mode $mode | Out-Null
    Assert-Condition ((Get-FileHash -LiteralPath $migrationConfig).Hash -eq $migratedHash) 'Repeated migration changed the managed configuration'
    & (Join-Path $project 'Restore.ps1') -ConfigDirectory $migrationTarget -BackupName $migrationBackup.Name | Out-Null
    Assert-Condition ((Get-FileHash -LiteralPath $migrationConfig).Hash -eq $originalHash) 'Migration restore changed the original bytes'
    Assert-Condition ((Get-Content (Join-Path $migrationTarget 'scripts/audio-panel.lua') -Raw) -eq 'old audio script') 'Migration restore lost the old script'
}
Write-Output 'Migration checks passed: all modes, preferences, native profiles, duplicates, BOM/CRLF, idempotence and exact restore.'

# Only this test-owned temporary directory is removed.
if ([IO.Path]::GetFullPath($sandbox).StartsWith([IO.Path]::GetFullPath($testRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
