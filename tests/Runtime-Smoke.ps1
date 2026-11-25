#requires -Version 5.1
<#
Runtime proof with the real OBS: installs presets into an isolated portable OBS config,
starts OBS recording, and reads what the encoder actually ran with from the OBS log.
Never touches %APPDATA%\obs-studio: OBS runs in portable mode from a junction copy in
%TEMP%, so the 600 MB install is not duplicated.

Needs OBS installed and a GPU for the hardware families. Local only (not in CI).

    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Runtime-Smoke.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Runtime-Smoke.ps1 -Preset 1080p60,youtube-1080p60 -Seconds 8

Two passes per preset: the record encoder as installed, then RecEncoder=none so the
recording runs on the stream encoder and its settings get logged too.
#>
[CmdletBinding()]
param(
    [string[]]$Preset = @('1080p60', 'youtube-1080p60', 'record-1080p60'),
    [ValidateSet('auto', 'nvenc', 'amf', 'qsv', 'x264')]
    [string]$Encoder = 'auto',
    [string]$ObsDir,
    [int]$Seconds = 6,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $Root 'lib\OBSForge.psm1') -Force

$Obs = Find-ForgeObs $ObsDir
if (-not $Obs) { Write-Host 'SKIP: OBS not installed'; exit 0 }
Write-Host "OBS $(Get-ForgeObsVersion $Obs) at $Obs"

$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("obsforge-smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$Portable = Join-Path $Work 'obs'
New-Item -ItemType Directory -Force -Path $Portable | Out-Null
foreach ($D in 'bin', 'data', 'core', 'obs-plugins') {
    $Src = Join-Path $Obs $D
    if (Test-Path -LiteralPath $Src) { New-Item -ItemType Junction -Path (Join-Path $Portable $D) -Target $Src | Out-Null }
}
Set-Content -LiteralPath (Join-Path $Portable 'portable_mode.txt') -Value ''
$Config = Join-Path $Portable 'config\obs-studio'
$RecDir = Join-Path $Work 'rec'
New-Item -ItemType Directory -Force -Path $Config, $RecDir | Out-Null
# Skip the first-run Auto-Configuration Wizard (frontend/widgets/OBSBasic.cpp FirstRun).
Set-Content -LiteralPath (Join-Path $Config 'user.ini') -Value "[General]`r`nFirstRun=true`r`n"
$env:OBSFORGE_BACKUP_ROOT = Join-Path $Work 'backups'

$I = & (Join-Path $Root 'Install.ps1') -ConfigRoot $Config -Preset $Preset -Encoder $Encoder -ObsDir $Obs -IgnoreRunning 6>&1 | Out-String
Write-Host ($I.Trim() -split "`r?`n" | Where-Object { $_ -match '^(Best|encoder|installed|scenes|  OBS-Forge)' } | Out-String).TrimEnd()

$Fail = 0
function Set-IniValue([string]$Path, [string]$Section, [string]$Key, [string]$Value) {
    $Ini = ConvertFrom-ForgeIniText ([System.IO.File]::ReadAllText($Path))
    if (-not $Ini.Contains($Section)) { $Ini[$Section] = [ordered]@{} }
    $Ini[$Section][$Key] = $Value
    [System.IO.File]::WriteAllText($Path, (ConvertTo-ForgeIniText $Ini), (New-Object System.Text.UTF8Encoding($true)))
}

function Invoke-ObsRecord([string]$ProfileName, [string]$Collection, [string]$Label) {
    $Bin = Join-Path $Portable 'bin\64bit'
    $LogDir = Join-Path $Config 'logs'
    $Before = @(Get-ChildItem -LiteralPath $LogDir -Filter *.txt -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $P = Start-Process -FilePath (Join-Path $Bin 'obs64.exe') -WorkingDirectory $Bin -PassThru -ArgumentList @(
        '--portable', '--multi', '--disable-updater', '--disable-shutdown-check', '--minimize-to-tray',
        '--profile', "`"$ProfileName`"", '--collection', "`"$Collection`"", '--startrecording')
    Start-Sleep -Seconds (4 + $Seconds)
    try { $P.Kill() } catch { }
    $P.WaitForExit(10000) | Out-Null
    Start-Sleep -Milliseconds 500
    $Log = Get-ChildItem -LiteralPath $LogDir -Filter *.txt | Where-Object { $Before -notcontains $_.FullName } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $Log) { return $null }
    return Get-Content -LiteralPath $Log.FullName -Raw
}

function Get-EncoderBlock([string]$Text) {
    # The settings block a hardware/x264 encoder logs when it starts.
    $M = [regex]::Match($Text, "(?s)\[(obs-nvenc|texture-amf|qsv|obs-x264)[^\]]*'advanced_video_(?:recording|stream)'\] (settings|preset|rate_control|profile)[^\r\n]*\r?\n((?:[^\r\n]*\t[^\r\n]*\r?\n){1,40})")
    if ($M.Success) { return $M.Value }
    $M = [regex]::Match($Text, "(?s)[^\r\n]*'advanced_video_(?:recording|stream)'[^\r\n]*\r?\n(?:[^\r\n]*\r?\n){0,30}")
    if ($M.Success) { return $M.Value }
    return ''
}

foreach ($P in (Get-ForgePreset $Preset)) {
    $Dir = Join-Path $Config "basic\profiles\$($P.Name)"
    $IniPath = Join-Path $Dir 'basic.ini'
    $Marker = Get-Content -LiteralPath (Join-Path $Dir 'obs-forge.json') -Raw | ConvertFrom-Json
    # OBS unescapes backslash sequences in INI values (libobs/util/config-file.c unescape),
    # so a raw C:\...\rec path would gain a carriage return. Use forward slashes.
    Set-IniValue $IniPath 'AdvOut' 'RecFilePath' ($RecDir.TrimEnd([char]92).Replace([char]92, [char]47))

    $Passes = @(@{ Label = 'record encoder'; Rec = $null })
    if ($Marker.recordEncoder -ne 'none') { $Passes += @{ Label = 'stream encoder'; Rec = 'none' } }
    $OrigRec = (ConvertFrom-ForgeIniText ([System.IO.File]::ReadAllText($IniPath)))['AdvOut']['RecEncoder']
    foreach ($Pass in $Passes) {
        if ($Pass.Rec) { Set-IniValue $IniPath 'AdvOut' 'RecEncoder' $Pass.Rec } else { Set-IniValue $IniPath 'AdvOut' 'RecEncoder' $OrigRec }
        $Text = Invoke-ObsRecord $P.Name $P.Collection $Pass.Label
        Write-Host ''
        Write-Host "== $($P.Name) / $($Pass.Label)"
        if (-not $Text) { Write-Host 'FAIL no OBS log written'; $Fail++; continue }
        $Errors = @()
        foreach ($Pat in 'does not support 8-bit output', 'Cannot perform 10-bit encode', 'output type .* failed to start', 'NVENC Error', 'Recording stopped because', "encoder '[^']*' failed") {
            if ($Text -match $Pat) { $Errors += $Pat }
        }
        if ($Text -match 'Recording Start') { Write-Host 'ok   recording started' } else { $Errors += 'recording did not start' }
        $Fmt = [regex]::Matches($Text, 'format:\s+(\S+)\s*\r?\n'); $Yuv = [regex]::Matches($Text, 'YUV mode:\s+([^\r\n]+)')
        if ($Fmt.Count) { Write-Host "ok   canvas $($Fmt[$Fmt.Count-1].Groups[1].Value) / $($Yuv[$Yuv.Count-1].Groups[1].Value)" }
        if ($Text -match "\[Loaded global audio device\]: 'Desktop Audio'") { Write-Host 'ok   Desktop Audio loaded' } else { $Errors += 'Desktop Audio not loaded' }
        if ($Text -match "\[Loaded global audio device\]: 'Mic/Aux'") { Write-Host 'ok   Mic/Aux loaded' } else { $Errors += 'Mic/Aux not loaded' }
        $Block = Get-EncoderBlock $Text
        if ($Block) { Write-Host ($Block.TrimEnd() -replace '(?m)^\S+: ', '     ') }
        else { $Errors += 'no encoder settings block in the log' }

        # Expected values from the files the installer wrote.
        $JsonName = 'recordEncoder.json'
        if ($Pass.Rec -eq 'none' -or $Marker.recordEncoder -eq 'none') { $JsonName = 'streamEncoder.json' }
        $J = Get-Content -LiteralPath (Join-Path $Dir $JsonName) -Raw | ConvertFrom-Json
        if ($Block -and $Marker.encoder -eq 'nvenc') {
            foreach ($Pair in @(@('preset', $J.preset), @('profile', $J.profile), @('rate_control', $J.rate_control), @('aq', ([string]$J.adaptive_quantization).ToLowerInvariant()), @('b-frames', $J.bf))) {
                if ($Block -match "$([regex]::Escape($Pair[0])):\s+(\S+)") {
                    if ($Matches[1] -eq "$($Pair[1])") { Write-Host "ok   $($Pair[0]) = $($Pair[1]) (from $JsonName)" }
                    else { $Errors += "$($Pair[0]) ran as $($Matches[1]), $JsonName says $($Pair[1])" }
                }
            }
        }
        if ($Errors.Count) { Write-Host "FAIL $($Errors -join '; ')"; $Fail++ }
    }
    Set-IniValue $IniPath 'AdvOut' 'RecEncoder' $OrigRec
}

$Files = @(Get-ChildItem -LiteralPath $RecDir -File -ErrorAction SilentlyContinue)
Write-Host ''
Write-Host "recordings written: $($Files.Count) ($(($Files | Measure-Object Length -Sum).Sum) bytes)"
if ($Files.Count -eq 0) { Write-Host 'FAIL no recording file'; $Fail++ }

if ($Keep) { Write-Host "kept: $Work" }
else {
    # Remove junctions first so the real OBS install is never followed by a recursive delete.
    foreach ($D in 'bin', 'data', 'core', 'obs-plugins') {
        $J = Join-Path $Portable $D
        if (Test-Path -LiteralPath $J) { [System.IO.Directory]::Delete($J) }
    }
    $Left = @(Get-ChildItem -LiteralPath $Portable -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    if ($Left.Count -eq 0) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "left in place (junctions still present): $Work" }
}
if ($Fail) { Write-Host "Runtime smoke: $Fail failure(s)"; exit 1 }
Write-Host 'Runtime smoke: PASS'
exit 0
