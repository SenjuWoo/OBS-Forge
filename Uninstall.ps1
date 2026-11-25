#requires -Version 5.1
<#
.SYNOPSIS
OBS-Forge uninstaller: removes only the profiles and scene collections this pack installed.

.DESCRIPTION
Profiles are recognised by their obs-forge.json marker (or the two 0.1.0 profile names).
Everything else in the OBS configuration folder is left alone. A backup goes to backups\
first; it can contain your stream key (service.json), so keep that folder private.

.EXAMPLE
.\Uninstall.ps1
.EXAMPLE
.\Uninstall.ps1 -Force                 # no prompt
.EXAMPLE
.\Uninstall.ps1 -Preset 720p30 -KeepScenes
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:APPDATA 'obs-studio'),
    [string[]]$Preset,
    [switch]$KeepScenes,
    [switch]$Force,
    [switch]$IgnoreRunning
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\OBSForge.psm1') -Force

if (-not $IgnoreRunning -and (Get-Process -Name obs64 -ErrorAction SilentlyContinue)) {
    throw 'OBS is running. Close it first.'
}

$Profiles = @(Get-ForgeInstalledProfile $ConfigRoot)
if ($Preset) {
    $Names = @(Get-ForgePreset $Preset | ForEach-Object { $_.Name })
    $Profiles = @($Profiles | Where-Object { $Names -contains $_.Name })
}
$Targets = New-Object System.Collections.ArrayList
foreach ($P in $Profiles) { [void]$Targets.Add($P.Path) }

if (-not $KeepScenes -and -not $Preset) {
    foreach ($C in (Get-ForgePreset | ForEach-Object { $_.Collection } | Select-Object -Unique)) {
        $Path = Join-Path $ConfigRoot "basic\scenes\$C.json"
        if (Test-Path -LiteralPath $Path) { [void]$Targets.Add($Path) }
        # OBS keeps a .bak next to each collection it saves.
        if (Test-Path -LiteralPath "$Path.bak") { [void]$Targets.Add("$Path.bak") }
    }
}

if ($Targets.Count -eq 0) {
    Write-Host 'Nothing to remove: OBS-Forge is not installed in this configuration folder.'
    exit 0
}

Write-Host 'This removes:'
$Targets | ForEach-Object { Write-Host "  $_" }
if (-not $Force) {
    $Answer = Read-Host 'Continue? (y/N)'
    if ($Answer -notmatch '^(y|yes)$') { Write-Host 'Cancelled.'; exit 0 }
}

$Backup = New-ForgeBackupDir 'uninstall-'
foreach ($T in $Targets) {
    $Leaf = Split-Path -Leaf $T
    Copy-Item -LiteralPath $T -Destination (Join-Path $Backup $Leaf) -Recurse -Force
    Remove-Item -LiteralPath $T -Recurse -Force
    Write-Host "removed: $Leaf"
}
Write-Host "backup:  $Backup"
Write-Host 'If OBS was set to an OBS-Forge profile or collection, it opens your previous/first one next time.'
exit 0
