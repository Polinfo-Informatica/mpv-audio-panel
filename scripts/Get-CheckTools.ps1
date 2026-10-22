# SPDX-License-Identifier: GPL-2.0-or-later
<#
.SYNOPSIS
Downloads pinned upstream check tools and verifies their release checksums.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$destination = Join-Path (Split-Path $PSScriptRoot) '.tools'
$null = New-Item -ItemType Directory -Path $destination -Force
$packages = @(
    @{ Name = 'selene'; Url = 'https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-windows.zip'; Hash = 'C8B693DE81D0DDC11490D8E1170DD98D775C2B21431144BD8286F738EF416109' },
    @{ Name = 'stylua'; Url = 'https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-windows-x86_64.zip'; Hash = 'FD13B4014E3B779C244BBC03F2C282E357F15BC526DE6A6FA5ECBC447538313C' },
    @{ Name = 'PSScriptAnalyzer'; Url = 'https://github.com/PowerShell/PSScriptAnalyzer/releases/download/1.25.0/PSScriptAnalyzer.1.25.0.nupkg'; Hash = '14E634C828EB98EFB9F40B2918BA90F139ED5ECCDF663A2A747736D996995D60' }
)
foreach ($package in $packages) {
    $archive = Join-Path $destination ($package.Name + '.zip')
    Invoke-WebRequest -Uri $package.Url -OutFile $archive -UseBasicParsing
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $package.Hash) {
        throw "Tool checksum mismatch: $($package.Name)"
    }
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $destination $package.Name) -Force
}
Write-Output 'Check tools are ready in .tools.'
