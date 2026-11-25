#requires -Version 5.1
<#
OBS-Forge verifier (read-only).

Checks that both profiles are SDR 8-bit Rec.709 and that the newest OBS log has no
NVENC colour/encoder errors. Exit code 0 = pass, 1 = something to fix.

    .\Verify.ps1
    .\Verify.ps1 -ConfigRoot 'D:\Portable\obs-studio'
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:APPDATA 'obs-studio')
)

$ErrorActionPreference = 'Stop'
$Fail = 0

function Ok([string]$Msg)   { Write-Host "ok   $Msg" }
function Bad([string]$Msg)  { Write-Host "FAIL $Msg"; $script:Fail++ }

$Profiles = Join-Path $ConfigRoot 'basic\profiles'
foreach ($Name in @('OBS-Forge 1080p60', 'OBS-Forge 1080p30')) {
    $Ini = Join-Path $Profiles "$Name\basic.ini"
    if (-not (Test-Path -LiteralPath $Ini)) { Bad "$Name missing"; continue }
    $Text = Get-Content -LiteralPath $Ini -Raw
    $Fmt = if ($Text -match 'ColorFormat=(\S+)') { $Matches[1] } else { '' }
    $Space = if ($Text -match 'ColorSpace=(\S+)') { $Matches[1] } else { '' }
    $Range = if ($Text -match 'ColorRange=(\S+)') { $Matches[1] } else { '' }
    $White = if ($Text -match 'SdrWhiteLevel=(\d+)') { $Matches[1] } else { '' }
    if ($Fmt -eq 'NV12' -and $Space -eq '709' -and $Range -eq 'Partial') {
        Ok "$Name SDR 8-bit $Space/$Fmt/$Range white=$White"
    }
    else {
        Bad "$Name is $Space/$Fmt/$Range - the H.264 stream encoder needs NV12/709/Partial"
    }

    $Enc = Join-Path $Profiles "$Name\streamEncoder.json"
    if (Test-Path -LiteralPath $Enc) {
        $J = Get-Content -LiteralPath $Enc -Raw | ConvertFrom-Json
        if ($J.profile -eq 'high' -and $J.rate_control -eq 'CBR') { Ok "$Name stream encoder H.264 High CBR $($J.bitrate) kbps" }
        else { Bad "$Name stream encoder is $($J.profile)/$($J.rate_control)" }
    }
    else { Bad "$Name streamEncoder.json missing" }

    $Rec = Join-Path $Profiles "$Name\recordEncoder.json"
    if (Test-Path -LiteralPath $Rec) {
        $J = Get-Content -LiteralPath $Rec -Raw | ConvertFrom-Json
        if ($J.profile -eq 'main') { Ok "$Name record encoder HEVC Main CQ $($J.cqp) P$($J.preset2.Substring(1))" }
        else { Bad "$Name record encoder profile is $($J.profile), expected main (8-bit)" }
    }
}

$LogDir = Join-Path $ConfigRoot 'logs'
$Log = Get-ChildItem -LiteralPath $LogDir -Filter '*.txt' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Log) {
    Write-Host 'note: no OBS log yet - run OBS once, then Verify.ps1 again'
}
else {
    $Text = Get-Content -LiteralPath $Log.FullName -Raw
    $Hits = @()
    if ($Text -match 'does not support 8-bit output of Rec\.?\s?2100') { $Hits += '8-bit Rec.2100' }
    if ($Text -match 'Cannot perform 10-bit encode') { $Hits += '10-bit on 8-bit encoder' }
    if ($Text -match "output type .* failed to start") { $Hits += 'output failed to start' }
    if ($Hits.Count -eq 0) { Ok "log $($Log.Name): no NVENC colour errors" }
    else { Bad "log $($Log.Name): $($Hits -join ', ')" }

    if ($Text -match 'format:\s+(\S+)') {
        $Fmt = $Matches[1]
        if ($Text -match 'YUV mode:\s+(.+)') { Ok "last canvas $Fmt / $($Matches[1].Trim())" }
    }
    if ($Text -match 'bits_per_color=(\d+)') {
        if ([int]$Matches[1] -ge 10) {
            Ok "display is HDR ($($Matches[1])-bit) - OBS canvas stays SDR and tone-maps"
        }
    }
}

Write-Host ''
if ($Fail -eq 0) { Write-Host 'Verify: PASS'; exit 0 }
Write-Host "Verify: $Fail check(s) failed"; exit 1