#requires -Version 5.1
<#
OBS-Forge installer.

Copies the two streaming profiles and the generic scene collection into an OBS
configuration folder. It writes only inside that folder, never touches profiles or
collections it does not own, and backs up anything it replaces.

    .\Install.ps1
    .\Install.ps1 -ConfigRoot 'D:\Portable\obs-studio'
    .\Install.ps1 -SkipScenes
    .\Install.ps1 -Force        # replace an existing OBS-Forge install without asking
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:APPDATA 'obs-studio'),
    [switch]$SkipScenes,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Version = '0.1.0'

Write-Host "OBS-Forge $Version"
Write-Host "config: $ConfigRoot"

if (Get-Process -Name obs64 -ErrorAction SilentlyContinue) {
    throw 'OBS is running. Close it first: OBS rewrites its configuration on exit and would undo this.'
}

$Profiles = Join-Path $ConfigRoot 'basic\profiles'
$Scenes = Join-Path $ConfigRoot 'basic\scenes'
New-Item -ItemType Directory -Force -Path $Profiles | Out-Null
New-Item -ItemType Directory -Force -Path $Scenes | Out-Null

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = Join-Path $Root "backups\$Stamp"
$BackedUp = $false

function Backup-One([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not $BackedUp) {
        New-Item -ItemType Directory -Force -Path $Backup | Out-Null
        $script:BackedUp = $true
    }
    $Name = Split-Path -Leaf $Path
    Copy-Item -LiteralPath $Path -Destination (Join-Path $Backup $Name) -Recurse -Force
    Write-Host "backup: $Name -> $Backup"
}

$ProfileNames = @('OBS-Forge 1080p60', 'OBS-Forge 1080p30')
foreach ($Name in $ProfileNames) {
    $Source = Join-Path $Root "profiles\$Name"
    if (-not (Test-Path -LiteralPath $Source)) { throw "Missing profile source: $Source" }
    $Dest = Join-Path $Profiles $Name
    if ((Test-Path -LiteralPath $Dest) -and -not $Force) {
        Write-Host "skip:   $Name already exists (use -Force to replace, backup is automatic)"
        continue
    }
    Backup-One $Dest
    if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
    Copy-Item -LiteralPath $Source -Destination $Dest -Recurse -Force
    Write-Host "profile: $Name"
}

if (-not $SkipScenes) {
    $SceneSource = Join-Path $Root 'scenes\OBS-Forge.json'
    $SceneDest = Join-Path $Scenes 'OBS-Forge.json'
    if ((Test-Path -LiteralPath $SceneDest) -and -not $Force) {
        Write-Host 'skip:   scene collection OBS-Forge already exists (use -Force to replace)'
    }
    else {
        Backup-One $SceneDest
        Copy-Item -LiteralPath $SceneSource -Destination $SceneDest -Force
        Write-Host 'scene:  OBS-Forge (Starting Soon, Live, BRB, Ending)'
    }
}

Write-Host ''
Write-Host 'Installed. Read back:'
foreach ($Name in $ProfileNames) {
    $Ini = Join-Path $Profiles "$Name\basic.ini"
    if (-not (Test-Path -LiteralPath $Ini)) { continue }
    $Text = Get-Content -LiteralPath $Ini -Raw
    $Fmt = if ($Text -match 'ColorFormat=(\S+)') { $Matches[1] } else { '?' }
    $Space = if ($Text -match 'ColorSpace=(\S+)') { $Matches[1] } else { '?' }
    $Range = if ($Text -match 'ColorRange=(\S+)') { $Matches[1] } else { '?' }
    $Fps = if ($Text -match 'FPSCommon=(\d+)') { $Matches[1] } else { '?' }
    $Bit = if ($Text -match 'VBitrate=(\d+)') { $Matches[1] } else { '?' }
    Write-Host ("  {0}: {1} fps, {2} kbps, {3}/{4}/{5}" -f $Name, $Fps, $Bit, $Fmt, $Space, $Range)
}

Write-Host ''
Write-Host 'Next:'
Write-Host '  1. Open OBS.'
Write-Host '  2. Profile menu -> OBS-Forge 1080p60 (or 1080p30 for a slower upload).'
Write-Host '  3. Settings -> Stream -> pick your service and connect your account.'
Write-Host '  4. Add your game capture in the Live scene, then Start Streaming.'
Write-Host '  5. Optional: .\Verify.ps1 checks the colour settings and the last OBS log.'