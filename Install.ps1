# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
Installs the configuration with a restorable backup of both managed files.
#>
[CmdletBinding()]
param([string]$ConfigDirectory = (Join-Path $env:APPDATA 'mpv'))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath($ConfigDirectory)
$files = @('mpv.conf', 'scripts/audio-panel.lua')
$checksums = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checksums.json') -Raw | ConvertFrom-Json

# Validate every source before changing the destination.
foreach ($relative in $files) {
    $source = Join-Path (Join-Path $PSScriptRoot 'config') $relative
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $checksums.$relative) {
        throw "Source checksum mismatch: $relative"
    }
}
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
$manifest = [pscustomobject]@{ Version = 1; Created = [DateTime]::UtcNow.ToString('o'); Files = $records }
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
try {
    foreach ($relative in $files) {
        $target = Join-Path $root $relative
        $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
        Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'config') $relative) -Destination $target -Force
    }
} catch {
    & (Join-Path $PSScriptRoot 'Restore.ps1') -ConfigDirectory $root -BackupName (Split-Path $backup -Leaf)
    throw
}
Write-Output 'Installation complete. Restart mpv.'
Write-Output "Backup: $backup"
Write-Output "Restore with Restore.ps1 -ConfigDirectory <config-directory> -BackupName $(Split-Path $backup -Leaf)"
