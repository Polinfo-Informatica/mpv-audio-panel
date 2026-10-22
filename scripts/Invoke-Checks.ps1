# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
Runs formatting, lint, package integrity and installer regression checks.
#>
[CmdletBinding()]
param([string]$ToolsDirectory = (Join-Path (Split-Path $PSScriptRoot) '.tools'))
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot
Push-Location $project
try {
    $luaFiles = @(Get-ChildItem ./config/scripts, ./tests -Filter *.lua -File | ForEach-Object FullName)
    & (Join-Path $ToolsDirectory 'stylua/stylua.exe') --check @luaFiles
    if ($LASTEXITCODE -ne 0) { throw 'StyLua check failed.' }
    & (Join-Path $ToolsDirectory 'selene/selene.exe') @luaFiles
    if ($LASTEXITCODE -ne 0) { throw 'Selene check failed.' }
    Import-Module (Join-Path $ToolsDirectory 'PSScriptAnalyzer/PSScriptAnalyzer.psd1') -Force
    $targets = @('Install.ps1', 'Restore.ps1', 'scripts', 'tests', 'PSScriptAnalyzerSettings.psd1')
    $diagnostics = @(foreach ($target in $targets) {
        Invoke-ScriptAnalyzer -Path $target -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    })
    if ($diagnostics.Count) { $diagnostics | Format-Table | Out-String | Write-Output; throw 'PowerShell lint failed.' }
    $checksums = Get-Content -LiteralPath ./checksums.json -Raw | ConvertFrom-Json
    foreach ($relative in @('mpv.conf', 'scripts/audio-panel.lua', 'scripts/video-safety.lua', 'mpv-audio-panel/audio.conf', 'mpv-audio-panel/video.conf')) {
        if ((Get-FileHash -LiteralPath (Join-Path ./config $relative)).Hash -ne $checksums.$relative) {
            throw "Package checksum mismatch: $relative"
        }
    }
    & ./tests/Installer.Tests.ps1
    Write-Output 'All static and installer checks passed.'
} finally {
    Pop-Location
}
