# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
Installs Audio, Video or Both components; offers a unified installation/restore menu.
#>
[CmdletBinding()]
param(
    [string]$ConfigDirectory = (Join-Path $env:APPDATA 'mpv'),
    [ValidateSet('Audio', 'Video', 'Both')][string]$Mode = 'Audio',
    [switch]$Menu,
    [Parameter(DontShow)][scriptblock]$MenuReader = { Read-Host 'Select an option (0-4)' }
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# The launcher has one entry point; explicit modes remain usable without prompts.
if ($Menu -and -not $PSBoundParameters.ContainsKey('Mode')) {
    Write-Output 'MPV Audio Panel'
    Write-Output '1 - Install or update Audio'
    Write-Output '2 - Install or update Video'
    Write-Output '3 - Install or update Both'
    Write-Output '4 - Restore the latest backup'
    Write-Output '0 - Exit without changes'
    do {
        $selection = & $MenuReader
        if ($null -eq $selection) { throw 'No menu selection was provided.' }
    } while ($selection -notin @('0', '1', '2', '3', '4'))
    if ($selection -eq '0') { return }
    if ($selection -eq '4') {
        & (Join-Path $PSScriptRoot 'Restore.ps1') -ConfigDirectory $ConfigDirectory
        return
    }
    $Mode = @{ '1' = 'Audio'; '2' = 'Video'; '3' = 'Both' }[$selection]
}
$root = [IO.Path]::GetFullPath($ConfigDirectory)
$audio = @('scripts/audio-panel.lua', 'mpv-audio-panel/audio.conf')
$video = @('scripts/video-safety.lua', 'mpv-audio-panel/video.conf')
$files = @('mpv.conf') + $audio + $video
$selected = @()
if ($Mode -ne 'Video') { $selected += $audio }
if ($Mode -ne 'Audio') { $selected += $video }
$checksums = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checksums.json') -Raw | ConvertFrom-Json

# Validate every source before changing the destination.
foreach ($relative in $files) {
    $source = Join-Path (Join-Path $PSScriptRoot 'config') $relative
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $checksums.$relative) {
        throw "Source checksum mismatch: $relative"
    }
    $target = Join-Path $root $relative
    if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "A directory occupies a managed file path: $relative"
    }
}
$config = Join-Path $root 'mpv.conf'
$existing = ''
if (Test-Path -LiteralPath $config) {
    # Migrate the original published complete configuration; the backup retains it.
    $legacyHash = '771651b1e41076bb3d111f8fafcf5191924389bc979aa26caf1d77a7adff7d7f'
    if ((Get-FileHash -LiteralPath $config).Hash -ne $legacyHash) {
        $existing = [IO.File]::ReadAllText($config)
    }
}
$pattern = '(?ms)^# BEGIN MPV AUDIO PANEL\r?\n.*?^# END MPV AUDIO PANEL(?:\r?\n|$)'
$existing = [regex]::Replace($existing, $pattern, '')
if ($existing -match '# (BEGIN|END) MPV AUDIO PANEL') { throw 'Incomplete managed configuration block. Restore or repair it first.' }
if ($existing -match '(?m)^\[(AUTO_MUSIC|AUDIO_PLAYBACK|HDR_ON|HDR_OFF|VIDEO_FALLBACK)\]\s*$') {
    throw 'Unmanaged package profiles were found. Back up and merge the configuration manually before installation.'
}
$loader = "# BEGIN MPV AUDIO PANEL`n[default]`n"
if ($Mode -ne 'Video') { $loader += "include=~~/mpv-audio-panel/audio.conf`n[default]`n" }
if ($Mode -ne 'Audio') { $loader += "include=~~/mpv-audio-panel/video.conf`n[default]`n" }
$loader += "# END MPV AUDIO PANEL`n"
$content = if ($existing.Length) { $existing.TrimEnd() + "`n`n" + $loader } else { $loader }
$backup = Join-Path (Join-Path $root 'mpv-audio-panel-backups') ([guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $backup -Force
$records = @()
foreach ($relative in $files) {
    $target = Join-Path $root $relative
    $exists = Test-Path -LiteralPath $target -PathType Leaf
    $hash = $null
    if ($exists) {
        $copy = Join-Path $backup $relative
        $null = New-Item -ItemType Directory -Path (Split-Path $copy) -Force
        Copy-Item -LiteralPath $target -Destination $copy
        $hash = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
    } elseif (Test-Path -LiteralPath $target) {
        throw "A directory occupies a managed file path: $relative"
    }
    $records += [pscustomobject]@{ Path = $relative; Existed = $exists; Hash = $hash }
}
$manifest = [pscustomobject]@{ Version = 2; Mode = $Mode; Created = [DateTime]::UtcNow.ToString('o'); Files = $records }
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
try {
    foreach ($relative in $audio + $video) {
        $target = Join-Path $root $relative
        if ($selected -contains $relative) {
            $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
            Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'config') $relative) -Destination $target -Force
        } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target
        }
    }
    [IO.File]::WriteAllText($config, $content, [Text.UTF8Encoding]::new($false))
} catch {
    & (Join-Path $PSScriptRoot 'Restore.ps1') -ConfigDirectory $root -BackupName (Split-Path $backup -Leaf)
    throw
}
Write-Output "Installation complete: $Mode. Restart mpv."
Write-Output "Backup: $backup"
Write-Output "Restore through Install.cmd, or Restore.ps1 -ConfigDirectory <config-directory> -BackupName $(Split-Path $backup -Leaf)"
