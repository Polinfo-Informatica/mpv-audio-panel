# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
Restores a selected installation backup; defaults to the latest backup.
#>
[CmdletBinding()]
param(
    [string]$ConfigDirectory = (Join-Path $env:APPDATA 'mpv'),
    [ValidatePattern('^[a-f0-9]{32}$')][string]$BackupName
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath($ConfigDirectory)
$backupRoot = Join-Path $root 'mpv-audio-panel-backups'
if (-not $BackupName) {
    $latest = Get-ChildItem -LiteralPath $backupRoot -Directory |
        Where-Object { $_.Name -match '^[a-f0-9]{32}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json')) } |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No installation backup was found.' }
    $BackupName = $latest.Name
}
$backup = Join-Path $backupRoot $BackupName
$manifest = Get-Content -LiteralPath (Join-Path $backup 'manifest.json') -Raw | ConvertFrom-Json
$expected = @('mpv.conf', 'scripts/audio-panel.lua')
if ($manifest.Version -ne 1 -or @($manifest.Files).Count -ne 2) { throw 'Invalid backup manifest.' }
foreach ($relative in $expected) {
    $record = @($manifest.Files | Where-Object Path -EQ $relative)
    if ($record.Count -ne 1 -or $record[0].Existed -isnot [bool]) { throw 'Invalid backup entry.' }
    if ($record[0].Existed) {
        $copy = Join-Path $backup $relative
        if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $record[0].Hash) {
            throw "Backup checksum mismatch: $relative"
        }
    }
}
# All backup contents have been validated before any target is modified.
foreach ($relative in $expected) {
    $record = $manifest.Files | Where-Object Path -EQ $relative
    $target = Join-Path $root $relative
    if ($record.Existed) {
        $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
        Copy-Item -LiteralPath (Join-Path $backup $relative) -Destination $target -Force
    } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target
    }
}
Write-Output 'Restore complete. Restart mpv. The backup has been retained.'
