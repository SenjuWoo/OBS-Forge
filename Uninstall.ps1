#requires -Version 5.1
<#
OBS-Forge uninstaller.

Removes only the profiles and the scene collection this pack installed. Everything
else in the OBS configuration folder is left alone. A backup goes to backups\ first.

    .\Uninstall.ps1
    .\Uninstall.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:APPDATA 'obs-studio'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

if (Get-Process -Name obs64 -ErrorAction SilentlyContinue) {
    throw 'OBS is running. Close it first.'
}

$Targets = @(
    (Join-Path $ConfigRoot 'basic\profiles\OBS-Forge 1080p60'),
    (Join-Path $ConfigRoot 'basic\profiles\OBS-Forge 1080p30'),
    (Join-Path $ConfigRoot 'basic\scenes\OBS-Forge.json')
) | Where-Object { Test-Path -LiteralPath $_ }

if ($Targets.Count -eq 0) {
    Write-Host 'Nothing to remove: OBS-Forge is not installed in this configuration folder.'
    exit 0
}

if (-not $Force) {
    Write-Host 'This removes:'
    $Targets | ForEach-Object { Write-Host "  $_" }
    $Answer = Read-Host 'Continue? (y/N)'
    if ($Answer -notmatch '^(y|Y)') { Write-Host 'Cancelled.'; exit 0 }
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = Join-Path $Root "backups\uninstall-$Stamp"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
foreach ($T in $Targets) {
    Copy-Item -LiteralPath $T -Destination (Join-Path $Backup (Split-Path -Leaf $T)) -Recurse -Force
    Remove-Item -LiteralPath $T -Recurse -Force
    Write-Host "removed: $(Split-Path -Leaf $T)"
}
Write-Host "backup:  $Backup"