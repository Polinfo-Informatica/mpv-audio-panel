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

# Exercise the actual menu in a child process rather than overriding native cmdlets.
function Invoke-InstallerMenu {
    param([string[]]$Choices, [string]$Target, [string]$ExplicitMode)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Process -Id $PID).Path
    $suffix = if ($ExplicitMode) { '-Mode ' + $ExplicitMode } else { '' }
    $start.Arguments = '-NoProfile -File "{0}" -ConfigDirectory "{1}" -Menu {2}' -f (Join-Path $project 'Install.ps1'), $Target, $suffix
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        foreach ($choice in $Choices) { $process.StandardInput.WriteLine($choice) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            throw 'Installer menu timed out.'
        }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw ($outputTask.Result + $errorTask.Result) }
    } finally {
        $process.Dispose()
    }
}
$menuTarget = Join-Path $sandbox 'menu'
Invoke-InstallerMenu -Choices @('invalid', '3') -Target $menuTarget
Assert-Condition (Test-Path (Join-Path $menuTarget 'scripts/audio-panel.lua')) 'Menu Both lost audio'
Assert-Condition (Test-Path (Join-Path $menuTarget 'scripts/video-safety.lua')) 'Menu Both lost video'
Invoke-InstallerMenu -Choices @('4') -Target $menuTarget
Assert-Condition (-not (Test-Path (Join-Path $menuTarget 'mpv.conf'))) 'Menu restore failed'
Invoke-InstallerMenu -Choices @('0') -Target $menuTarget
Assert-Condition (-not (Test-Path (Join-Path $menuTarget 'mpv.conf'))) 'Menu cancel changed configuration'
foreach ($choice in @('1', '2')) {
    Invoke-InstallerMenu -Choices @($choice) -Target $menuTarget
    Assert-Condition ((Test-Path (Join-Path $menuTarget 'scripts/audio-panel.lua')) -eq ($choice -eq '1')) 'Menu audio selection failed'
    Assert-Condition ((Test-Path (Join-Path $menuTarget 'scripts/video-safety.lua')) -eq ($choice -eq '2')) 'Menu video selection failed'
}
Invoke-InstallerMenu -Choices @() -Target $menuTarget -ExplicitMode Both
Assert-Condition (Test-Path (Join-Path $menuTarget 'scripts/audio-panel.lua')) 'Explicit mode lost audio'
Assert-Condition (Test-Path (Join-Path $menuTarget 'scripts/video-safety.lua')) 'Explicit mode lost video'
Write-Output 'Unified menu checks passed: all modes, restore, invalid input, cancel and explicit mode.'

# Only this test-owned temporary directory is removed.
if ([IO.Path]::GetFullPath($sandbox).StartsWith([IO.Path]::GetFullPath($testRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
