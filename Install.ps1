#requires -Version 5.1
<#
.SYNOPSIS
OBS-Forge installer: streaming / recording profiles and a ready scene collection for OBS.

.DESCRIPTION
Writes OBS profiles built from presets\presets.psd1 for the encoder your PC has (NVIDIA
NVENC, AMD AMF, Intel Quick Sync, or x264 on the CPU - detected with OBS's own encoder
probes), plus the OBS-Forge scene collection. It writes only inside the OBS configuration
folder, never touches profiles or collections it does not own, and backs up anything it
changes into backups\.

Upgrading keeps your connected account (service.json), hotkeys and the settings you
changed yourself; it re-applies the video and encoder settings.

.EXAMPLE
.\Install.ps1                          # recommended presets (1080p60 + 1080p30), auto encoder
.EXAMPLE
.\Install.ps1 -Menu                    # pick presets from a list (what Install.cmd runs)
.EXAMPLE
.\Install.ps1 -Preset 720p60,youtube-1080p60 -Encoder amf
.EXAMPLE
.\Install.ps1 -Preset all -Launch      # everything, then open OBS on the first preset
.EXAMPLE
.\Install.ps1 -List                    # show presets and the encoder this PC would use
.EXAMPLE
.\Install.ps1 -ConfigRoot 'D:\Portable\obs-studio\config\obs-studio'
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:APPDATA 'obs-studio'),
    [string[]]$Preset,
    [ValidateSet('auto', 'nvenc', 'amf', 'qsv', 'x264')]
    [string]$Encoder = 'auto',
    [string]$ObsDir,
    [switch]$Menu,
    [switch]$List,
    [switch]$SkipScenes,
    [switch]$Force,
    [switch]$Launch,
    [switch]$NoProbe,
    [switch]$IgnoreRunning
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\OBSForge.psm1') -Force
$Version = Get-ForgeVersion
$Families = Get-ForgeFamilies

Write-Host "OBS-Forge $Version"

# --- what is on this PC -----------------------------------------------------------------
$Obs = Find-ForgeObs $ObsDir
$ObsVersion = Get-ForgeObsVersion $Obs
$Caps = Get-ForgeCaps -ObsDir $Obs -NoProbe:$NoProbe
$Detected = Select-ForgeEncoder $Caps

if ($Obs) { Write-Host "OBS:    $ObsVersion ($Obs)" }
else { Write-Host 'OBS:    not found (portable OBS or not installed yet - profiles are written anyway)' }
$GpuText = ($Caps.Gpus -join ', ')
if (-not $GpuText) { $GpuText = 'unknown' }
$ProbeText = @{ 'obs-probe' = "OBS encoder probe"; 'gpu-name' = 'GPU name (OBS not found)'; 'none' = 'nothing detected' }[$Caps.Source]
Write-Host "GPU:    $GpuText"
Write-Host "Best:   $($Families[$Detected].Label) (from $ProbeText)"
if ($ObsVersion -and $ObsVersion -lt [version]'31.0') {
    Write-Warning "OBS $ObsVersion is older than 31: its NVENC encoder ids differ and HEVC streaming is missing. Update OBS (33+ is tested)."
}

function Show-PresetTable {
    param($All)
    $Group = ''
    $N = 0
    foreach ($P in $All) {
        $N++
        if ($P.Group -ne $Group) { $Group = $P.Group; Write-Host ''; Write-Host "  $Group" }
        $Mark = ''
        if ($P.Recommended) { $Mark = '  [recommended]' }
        Write-Host ('   {0,2}) {1,-20} {2}{3}' -f $N, $P.Id, $P.For, $Mark)
    }
    Write-Host ''
}

$AllPresets = Get-ForgePreset

if ($List) {
    Show-PresetTable $AllPresets
    Write-Host 'Encoders: auto (default), nvenc, amf, qsv, x264'
    exit 0
}

# --- choose presets and encoder ---------------------------------------------------------
if ($Menu) {
    Write-Host ''
    Write-Host 'Pick what you want OBS set up for:'
    Show-PresetTable $AllPresets
    $Answer = Read-Host 'Numbers separated by commas, A for all, Enter for the recommended pair'
    $Answer = "$Answer".Trim()
    if (-not $Answer) { $Preset = @('recommended') }
    elseif ($Answer -match '^(a|all)$') { $Preset = @('all') }
    else {
        $Preset = foreach ($Tok in ($Answer -split '[,\s]+' | Where-Object { $_ })) {
            if ($Tok -match '^\d+$' -and [int]$Tok -ge 1 -and [int]$Tok -le $AllPresets.Count) { $AllPresets[[int]$Tok - 1].Id }
            else { $Tok }
        }
    }

    $Pick = Read-Host "Encoder [Enter = $Detected, or nvenc / amf / qsv / x264]"
    $Pick = "$Pick".Trim().ToLowerInvariant()
    if ($Pick) {
        if (-not $Families.Contains($Pick)) { throw "Unknown encoder '$Pick'. Use nvenc, amf, qsv or x264." }
        $Encoder = $Pick
    }
}

$Selected = Get-ForgePreset $(if ($Preset) { $Preset } else { @('recommended') })
$Family = $Encoder
if ($Family -eq 'auto') { $Family = $Detected }
$Available = Test-ForgeEncoderAvailable $Family $Caps
if ($Available -eq $false) {
    # A choice, not a block: the user may be preparing a config for another PC.
    Write-Warning "$($Families[$Family].Label) was not detected on this PC. OBS will refuse to start the stream with it here."
}

Write-Host ''
Write-Host "config:  $ConfigRoot"
Write-Host "encoder: $($Families[$Family].Label)"
Write-Host ("presets: " + (($Selected | ForEach-Object { $_.Id }) -join ', '))

if (-not $IgnoreRunning -and (Get-Process -Name obs64 -ErrorAction SilentlyContinue)) {
    throw 'OBS is running. Close it first: OBS rewrites its configuration on exit and would undo this. (-IgnoreRunning skips this check for a different config folder.)'
}

New-Item -ItemType Directory -Force -Path (Join-Path $ConfigRoot 'basic\profiles') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ConfigRoot 'basic\scenes') | Out-Null

# One backup folder per run, created only when something is replaced.
$script:BackupDir = $null
$GetBackupDir = {
    if (-not $script:BackupDir) { $script:BackupDir = New-ForgeBackupDir }
    $script:BackupDir
}

Write-ForgeLog "install start version=$Version config=$ConfigRoot encoder=$Family caps=$($Caps.Source) presets=$(($Selected | ForEach-Object { $_.Id }) -join ',')" (Join-Path $env:LOCALAPPDATA 'OBS-Forge')

Write-Host ''
$Results = foreach ($P in $Selected) {
    $Build = Get-ForgeProfileBuild $P $Family $Caps
    $R = Install-ForgeProfile -ConfigRoot $ConfigRoot -Build $Build -Force:$Force -GetBackupDir $GetBackupDir
    $Note = ''
    if ($R.Reason) { $Note = " ($($R.Reason))" }
    Write-Host ('{0,-10} {1}{2}' -f "$($R.Action):", $R.Name, $Note)
    if ($Build.StreamPlan.Codec -ne $P.StreamCodec) {
        Write-Host "           stream falls back to H.264 at $($Build.StreamPlan.Kbps) kbps (no HEVC on this encoder)"
    }
    $R
}

# --- scene collections ------------------------------------------------------------------
if (-not $SkipScenes) {
    $Collections = $Selected | ForEach-Object { $_.Collection } | Select-Object -Unique
    foreach ($C in $Collections) {
        $Dest = Join-Path $ConfigRoot "basic\scenes\$C.json"
        $Size = Get-ForgeCollectionSize $C
        if ((Test-Path -LiteralPath $Dest) -and -not $Force) {
            # Your scenes stay yours. Only add the audio devices 0.1.0 forgot.
            $Backup = & $GetBackupDir
            Copy-Item -LiteralPath $Dest -Destination (Join-Path $Backup "$C.json") -Force
            if (Add-ForgeMissingAudio $Dest $C) { Write-Host "updated:   scene collection $C (added Desktop Audio + Mic/Aux)" }
            else { Write-Host "kept:      scene collection $C (yours; -Force replaces it)" }
            continue
        }
        if (Test-Path -LiteralPath $Dest) {
            $Backup = & $GetBackupDir
            Copy-Item -LiteralPath $Dest -Destination (Join-Path $Backup "$C.json") -Force
        }
        $Json = New-ForgeCollection $C $Size.Width $Size.Height
        [System.IO.File]::WriteAllText($Dest, $Json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "scenes:    $C ($($Size.Width)x$($Size.Height): Starting Soon, Live with Game Capture, BRB, Ending, Desktop Audio, Mic/Aux)"
    }
}

if ($script:BackupDir) { Write-Host "backup:    $script:BackupDir" }

# --- read back --------------------------------------------------------------------------
Write-Host ''
Write-Host 'Read back:'
foreach ($P in $Selected) {
    $Dir = Join-Path $ConfigRoot "basic\profiles\$($P.Name)"
    $Ini = Join-Path $Dir 'basic.ini'
    $SJson = Join-Path $Dir 'streamEncoder.json'
    if (-not (Test-Path -LiteralPath $Ini) -or -not (Test-Path -LiteralPath $SJson)) { continue }
    $I = ConvertFrom-ForgeIniText ([System.IO.File]::ReadAllText($Ini))
    if (-not $I.Contains('Video') -or -not $I.Contains('AdvOut')) { continue }
    $S = Get-Content -LiteralPath $SJson -Raw | ConvertFrom-Json
    $V = $I['Video']
    Write-Host ('  {0}: {1}x{2} {3} fps, {4} {5} kbps, {6}/{7}/{8}' -f $P.Name, $V['OutputCX'], $V['OutputCY'], $V['FPSCommon'],
        $I['AdvOut']['Encoder'], $S.bitrate, $V['ColorFormat'], $V['ColorSpace'], $V['ColorRange'])
}

$First = $Selected[0]
$Collection = $First.Collection
Write-Host ''
Write-Host 'Next:'
Write-Host "  1. Open OBS. If the Auto-Configuration Wizard opens (first start only), Cancel it - it would overwrite these settings."
Write-Host "  2. Profile menu -> $($First.Name).  Scene Collection menu -> $Collection."
Write-Host '  3. Settings -> Stream -> pick your service -> Connect Account (or paste your stream key).'
Write-Host '  4. Start your game in fullscreen: the Live scene captures it. Then Start Streaming.'
Write-Host '  5. Check it any time: Verify.cmd (or .\Verify.ps1).'

$DoLaunch = $Launch
if ($Menu -and -not $Launch -and $Obs) {
    $A = Read-Host "Open OBS now on '$($First.Name)'? (Y/n)"
    if ("$A".Trim() -notmatch '^(n|no)$') { $DoLaunch = $true }
}
if ($DoLaunch) {
    if (-not $Obs) { Write-Warning 'OBS not found; open it yourself.' }
    elseif ($ConfigRoot -ne (Join-Path $env:APPDATA 'obs-studio')) { Write-Warning 'Not launching: -ConfigRoot is not the default OBS config folder.' }
    else {
        # --profile / --collection make OBS open on them and remember them; no config edit.
        $Bin = Join-Path $Obs 'bin\64bit'
        Start-Process -FilePath (Join-Path $Bin 'obs64.exe') -WorkingDirectory $Bin -ArgumentList @('--profile', "`"$($First.Name)`"", '--collection', "`"$Collection`"")
        Write-Host "Started OBS on $($First.Name) / $Collection."
    }
}

Write-ForgeLog "install done: $((@($Results) | ForEach-Object { "$($_.Name)=$($_.Action)" }) -join '; ')" (Join-Path $env:LOCALAPPDATA 'OBS-Forge')
exit 0
