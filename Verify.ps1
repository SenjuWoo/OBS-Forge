#requires -Version 5.1
<#
.SYNOPSIS
OBS-Forge doctor (read-only): checks every installed OBS-Forge profile, the scene
collections, the encoder this PC really has, and the newest OBS log.

.DESCRIPTION
ok   = as installed
warn = changed in OBS or worth knowing; does not fail
FAIL = will break the stream or the colours; exit code 1

.EXAMPLE
.\Verify.ps1
.EXAMPLE
.\Verify.ps1 -ConfigRoot 'D:\Portable\obs-studio\config\obs-studio'
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:APPDATA 'obs-studio'),
    [string]$ObsDir,
    [switch]$NoProbe
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\OBSForge.psm1') -Force
$Families = Get-ForgeFamilies
$script:Fail = 0
$script:Warn = 0

function Ok([string]$Msg) { Write-Host "ok   $Msg" }
function Warn([string]$Msg) { Write-Host "warn $Msg"; $script:Warn++ }
function Bad([string]$Msg) { Write-Host "FAIL $Msg"; $script:Fail++ }

function Read-Json([string]$Path) {
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { return $null }
}
function Prop($Obj, [string]$Name) {
    # Property value or $null, without throwing on a missing key.
    if ($null -eq $Obj) { return $null }
    $P = $Obj.PSObject.Properties[$Name]
    if ($P) { return $P.Value }
    return $null
}

Write-Host "OBS-Forge $(Get-ForgeVersion) verify: $ConfigRoot"

$Obs = Find-ForgeObs $ObsDir
$ObsVersion = Get-ForgeObsVersion $Obs
if ($ObsVersion) {
    if ($ObsVersion -ge [version]'31.0') { Ok "OBS $ObsVersion" }
    else { Bad "OBS $ObsVersion is older than 31 - the obs_nvenc_* encoders do not exist there; update OBS" }
}
else { Write-Host 'note OBS install not found (portable OBS?) - encoder availability not checked' }
$Caps = Get-ForgeCaps -ObsDir $Obs -NoProbe:$NoProbe

# Encoder id -> family, for profiles the user re-pointed in OBS.
$IdFamily = @{}
foreach ($F in $Families.Keys) {
    if ($Families[$F].H264) { $IdFamily[$Families[$F].H264] = $F }
    if ($Families[$F].Hevc) { $IdFamily[$Families[$F].Hevc] = $F }
}
foreach ($Legacy in 'jim_nvenc', 'jim_hevc_nvenc', 'ffmpeg_nvenc', 'obs_nvenc_av1_tex') { $IdFamily[$Legacy] = 'nvenc' }
$LegacyNvencKeys = @{ preset2 = 'preset'; psycho_aq = 'adaptive_quantization' }

$Installed = Get-ForgeInstalledProfile $ConfigRoot
if ($Installed.Count -eq 0) { Bad "no OBS-Forge profile in $ConfigRoot\basic\profiles - run Install.ps1" }

$Presets = @{}
foreach ($P in Get-ForgePreset) { $Presets[$P.Id] = $P }

foreach ($Prof in $Installed) {
    $Name = $Prof.Name
    $Dir = $Prof.Path
    $M = $Prof.Marker
    $Preset = $Presets[$Prof.Preset]
    if ($Prof.Legacy) { Warn "$Name was installed by 0.1.0 - run Install.ps1 to upgrade (keeps your account and hotkeys)" }

    $IniPath = Join-Path $Dir 'basic.ini'
    if (-not (Test-Path -LiteralPath $IniPath)) { Bad "$Name basic.ini missing"; continue }
    $Ini = ConvertFrom-ForgeIniText ([System.IO.File]::ReadAllText($IniPath))
    $Video = @{}; if ($Ini.Contains('Video')) { $Video = $Ini['Video'] }
    $Adv = @{}; if ($Ini.Contains('AdvOut')) { $Adv = $Ini['AdvOut'] }
    $Out = @{}; if ($Ini.Contains('Output')) { $Out = $Ini['Output'] }

    # Colour: the one thing that stops an 8-bit stream encoder from starting.
    $Fmt = $Video['ColorFormat']; $Space = $Video['ColorSpace']; $Range = $Video['ColorRange']
    if ($Fmt -eq 'NV12' -and $Space -eq '709' -and $Range -eq 'Partial') {
        Ok "$Name SDR 8-bit $Space/$Fmt/$Range white=$($Video['SdrWhiteLevel'])"
    }
    else { Bad "$Name is $Space/$Fmt/$Range - the 8-bit stream encoder needs NV12/709/Partial (docs\HDR.md)" }

    # Canvas / fps drift against the preset.
    if ($Preset) {
        $Want = "$($Preset.Width)x$($Preset.Height)@$($Preset.Fps)"
        $Have = "$($Video['OutputCX'])x$($Video['OutputCY'])@$($Video['FPSCommon'])"
        if ($Want -eq $Have) { Ok "$Name canvas $Have" } else { Warn "$Name canvas is $Have, preset is $Want (changed in OBS)" }
    }

    if ($Out['Mode'] -ne 'Advanced') { Warn "$Name output mode is $($Out['Mode']) - the pack's separate stream/record encoders need Advanced" }

    # Stream encoder.
    $StreamId = $Adv['Encoder']
    $Family = $IdFamily[$StreamId]
    $S = Read-Json (Join-Path $Dir 'streamEncoder.json')
    if (-not $S) { Bad "$Name streamEncoder.json missing or unreadable" }
    else {
        $Prof_ = [string](Prop $S 'profile'); $Rc = [string](Prop $S 'rate_control'); $Kbps = Prop $S 'bitrate'
        $IsStreamPreset = (-not $Preset) -or ($Preset.Record -ne 'quality')
        if ($Prof_ -match '10') { Bad "$Name stream encoder profile $Prof_ is 10-bit - an SDR 8-bit canvas cannot feed it" }
        elseif ($Rc -ne 'CBR' -and $IsStreamPreset) { Bad "$Name stream rate control is '$Rc' - Twitch/YouTube/Kick expect CBR" }
        else { Ok "$Name stream $StreamId $Prof_ $Rc $Kbps kbps" }
        if ($M -and $Kbps -and [int]$Kbps -ne [int]$M.streamKbps) { Warn "$Name stream bitrate $Kbps kbps, pack set $($M.streamKbps) (changed in OBS)" }
        if ($Family -eq 'nvenc') {
            foreach ($K in $LegacyNvencKeys.Keys) {
                if ((Prop $S $K) -ne $null -and (Prop $S $LegacyNvencKeys[$K]) -eq $null) {
                    Bad "$Name streamEncoder.json uses '$K', which OBS 31+ ignores (it reads '$($LegacyNvencKeys[$K])') - run Install.ps1"
                }
            }
        }
    }

    # Encoder availability on this PC.
    if ($Family) {
        $Avail = Test-ForgeEncoderAvailable $Family $Caps
        if ($Avail -eq $true) { Ok "$Name encoder $($Families[$Family].Label) available on this PC" }
        elseif ($Avail -eq $false) { Bad "$Name uses $($Families[$Family].Label), which this PC does not have - run Install.ps1 (auto-detects) or Install.ps1 -Encoder <yours>" }
    }
    elseif ($StreamId) { Warn "$Name stream encoder '$StreamId' is not one the pack knows" }

    # Record encoder.
    $RecId = $Adv['RecEncoder']
    if ($RecId -eq 'none') { Ok "$Name recording shares the stream encoder" }
    elseif ($RecId) {
        $R = Read-Json (Join-Path $Dir 'recordEncoder.json')
        if (-not $R) { Bad "$Name recordEncoder.json missing or unreadable (RecEncoder=$RecId)" }
        else {
            $RProf = [string](Prop $R 'profile')
            if ($RProf -match '10') { Bad "$Name record encoder profile $RProf is 10-bit - never on an SDR canvas" }
            else {
                $Q = Prop $R 'cqp'; if ($null -eq $Q) { $Q = Prop $R 'crf' }
                $Pr = Prop $R 'preset'; if ($null -eq $Pr) { $Pr = Prop $R 'target_usage' }
                Ok "$Name record $RecId $RProf $(Prop $R 'rate_control') $Q $Pr"
            }
            if ($IdFamily[$RecId] -eq 'nvenc') {
                foreach ($K in $LegacyNvencKeys.Keys) {
                    if ((Prop $R $K) -ne $null -and (Prop $R $LegacyNvencKeys[$K]) -eq $null) {
                        Bad "$Name recordEncoder.json uses '$K', which OBS 31+ ignores (it reads '$($LegacyNvencKeys[$K])') - run Install.ps1"
                    }
                }
            }
        }
    }
}

# Scene collections: a collection without global audio devices streams silence.
$SceneDir = Join-Path $ConfigRoot 'basic\scenes'
foreach ($C in (Get-ForgePreset | ForEach-Object { $_.Collection } | Select-Object -Unique)) {
    $Path = Join-Path $SceneDir "$C.json"
    if (-not (Test-Path -LiteralPath $Path)) { continue }
    $J = Read-Json $Path
    if (-not $J) { Bad "scene collection $C is not valid JSON"; continue }
    $Missing = @()
    if ($null -eq (Prop $J 'DesktopAudioDevice1')) { $Missing += 'Desktop Audio' }
    if ($null -eq (Prop $J 'AuxAudioDevice1')) { $Missing += 'Mic/Aux' }
    if ($Missing.Count) { Warn "scene collection $C has no $($Missing -join ' / ') - run Install.ps1 to add them, or add them in Settings -> Audio" }
    else { Ok "scene collection $C has Desktop Audio and Mic/Aux" }
}

# Newest OBS log.
$LogDir = Join-Path $ConfigRoot 'logs'
$Log = Get-ChildItem -LiteralPath $LogDir -Filter '*.txt' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Log) {
    Write-Host 'note no OBS log yet - run OBS once, then Verify again'
}
else {
    $Text = Get-Content -LiteralPath $Log.FullName -Raw
    $Hits = @()
    if ($Text -match 'does not support 8-bit output of Rec\.?\s?2100') { $Hits += '8-bit Rec.2100' }
    if ($Text -match 'Cannot perform 10-bit encode') { $Hits += '10-bit on 8-bit encoder' }
    if ($Text -match 'output type .* failed to start') { $Hits += 'output failed to start' }
    if ($Text -match 'Failed to (create|initialize) (the )?encoder|encoder .* failed to initialize') { $Hits += 'encoder failed to initialize' }
    if ($Hits.Count -eq 0) { Ok "log $($Log.Name): no encoder or colour errors" }
    else { Bad "log $($Log.Name): $($Hits -join ', ')" }

    # The last video reset is what OBS ran with last.
    $Fmts = [regex]::Matches($Text, '(?m)^\S*\s*format:\s+(\S+)\s*$')
    $Yuv = [regex]::Matches($Text, 'YUV mode:\s+(.+)')
    if ($Fmts.Count -gt 0 -and $Yuv.Count -gt 0) {
        Ok "log last canvas $($Fmts[$Fmts.Count - 1].Groups[1].Value) / $($Yuv[$Yuv.Count - 1].Groups[1].Value.Trim())"
    }
    $Bits = [regex]::Matches($Text, 'bits_per_color=(\d+)')
    if ($Bits.Count -gt 0 -and [int]$Bits[$Bits.Count - 1].Groups[1].Value -ge 10) {
        Ok "display is HDR ($($Bits[$Bits.Count - 1].Groups[1].Value)-bit) - the OBS canvas stays SDR and tone-maps"
    }
}

Write-Host ''
if ($script:Fail -eq 0) {
    $W = ''
    if ($script:Warn) { $W = " ($script:Warn warning(s))" }
    Write-Host "Verify: PASS$W"
    exit 0
}
Write-Host "Verify: $script:Fail check(s) failed"
exit 1
