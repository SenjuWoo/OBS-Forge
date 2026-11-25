#requires -Version 5.1
<#
OBS-Forge shared module: preset catalogue, encoder capability probe, profile and scene
collection builders, install/upgrade logic. Used by Install.ps1, Verify.ps1 and
Uninstall.ps1. Windows PowerShell 5.1 and PowerShell 7 compatible (no ternary, no ??).

Every OBS key written here was checked against the OBS 33.0.2 source:
  plugins/obs-nvenc/nvenc-properties.c   (obs_nvenc_*: preset, adaptive_quantization, ...)
  plugins/obs-ffmpeg/texture-amf.cpp     (h264_texture_amf / h265_texture_amf)
  plugins/obs-qsv11/obs-qsv11.c          (obs_qsv11_v2 / obs_qsv11_hevc)
  plugins/obs-x264/obs-x264.c            (obs_x264)
  frontend/utility/AdvancedOutput.cpp    ([AdvOut] keys)
  frontend/widgets/OBSBasic_SceneCollections.cpp (global audio device keys)
#>

$script:PackVersion = '0.2.0'
$script:PackRoot = Split-Path -Parent $PSScriptRoot
$script:MarkerName = 'obs-forge.json'
$script:ProfilePrefix = 'OBS-Forge '
# 0.1.0 shipped these two profiles without a marker file.
$script:LegacyProfiles = @{ 'OBS-Forge 1080p60' = '1080p60'; 'OBS-Forge 1080p30' = '1080p30' }
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Encoder families. Ids are OBS 33 encoder ids; Simple* are [SimpleOutput] encoder names
# (frontend/widgets/OBSBasic.hpp SIMPLE_ENCODER_*), used only if the user switches OBS to
# Simple output mode.
$script:Families = [ordered]@{
    nvenc = @{ Label = 'NVIDIA NVENC'; H264 = 'obs_nvenc_h264_tex'; Hevc = 'obs_nvenc_hevc_tex'; Simple = 'nvenc'; SimpleHevc = 'nvenc_hevc' }
    amf   = @{ Label = 'AMD AMF'; H264 = 'h264_texture_amf'; Hevc = 'h265_texture_amf'; Simple = 'amd'; SimpleHevc = 'amd_hevc' }
    qsv   = @{ Label = 'Intel Quick Sync'; H264 = 'obs_qsv11_v2'; Hevc = 'obs_qsv11_hevc'; Simple = 'qsv'; SimpleHevc = 'qsv' }
    x264  = @{ Label = 'x264 (CPU)'; H264 = 'obs_x264'; Hevc = $null; Simple = 'x264'; SimpleHevc = 'x264' }
}

function Get-ForgeVersion { $script:PackVersion }
function Get-ForgeFamilies { $script:Families }

function Write-ForgeLog {
    # Quiet diagnostic log next to the backups; never fails the caller.
    param([string]$Message, [string]$Root)
    try {
        if (-not $Root) { return }
        $Dir = Join-Path $Root 'logs'
        if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
        $Line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
        [System.IO.File]::AppendAllText((Join-Path $Dir 'obs-forge.log'), $Line + "`r`n", $script:Utf8NoBom)
    }
    catch { }
}

# --------------------------------------------------------------------------------------
# Presets
# --------------------------------------------------------------------------------------

function Get-ForgePreset {
    <# Returns preset hashtables. -Id accepts ids, profile names, 'recommended' or 'all'. #>
    param([string[]]$Id)
    $Data = Import-PowerShellDataFile -LiteralPath (Join-Path $script:PackRoot 'presets\presets.psd1')
    $All = @($Data.Presets)
    foreach ($P in $All) {
        if (-not $P.Name.StartsWith($script:ProfilePrefix)) { throw "Preset $($P.Id): Name must start with '$($script:ProfilePrefix)'" }
        if (-not $P.ContainsKey('Recommended')) { $P.Recommended = $false }
        if (-not $P.ContainsKey('H264Kbps')) { $P.H264Kbps = $P.StreamKbps }
        if (-not $P.ContainsKey('StreamRescale')) { $P.StreamRescale = '' }
    }
    if (-not $Id -or $Id.Count -eq 0) { return $All }

    $Out = New-Object System.Collections.ArrayList
    foreach ($Raw in $Id) {
        foreach ($Want in ($Raw -split ',')) {
            $Want = $Want.Trim()
            if (-not $Want) { continue }
            if ($Want -eq 'all') { $All | ForEach-Object { [void]$Out.Add($_) }; continue }
            if ($Want -eq 'recommended') { $All | Where-Object { $_.Recommended } | ForEach-Object { [void]$Out.Add($_) }; continue }
            $Hit = $All | Where-Object { $_.Id -eq $Want -or $_.Name -eq $Want -or $_.Name -eq ($script:ProfilePrefix + $Want) } | Select-Object -First 1
            if (-not $Hit) {
                $Known = ($All | ForEach-Object { $_.Id }) -join ', '
                throw "Unknown preset '$Want'. Known: $Known, recommended, all"
            }
            [void]$Out.Add($Hit)
        }
    }
    # De-duplicate, keep order.
    $Seen = @{}
    $Unique = foreach ($P in $Out) { if (-not $Seen.ContainsKey($P.Id)) { $Seen[$P.Id] = $true; $P } }
    return @($Unique)
}

# --------------------------------------------------------------------------------------
# OBS install + encoder capability probe
# --------------------------------------------------------------------------------------

function Find-ForgeObs {
    <# Returns the OBS install folder (contains bin\64bit\obs64.exe) or $null. #>
    param([string]$ObsDir)
    $Candidates = New-Object System.Collections.ArrayList
    if ($ObsDir) { [void]$Candidates.Add($ObsDir) }
    foreach ($Key in 'HKLM:\SOFTWARE\OBS Studio', 'HKLM:\SOFTWARE\WOW6432Node\OBS Studio', 'HKCU:\SOFTWARE\OBS Studio') {
        try {
            $V = (Get-ItemProperty -LiteralPath $Key -ErrorAction Stop).'(default)'
            if ($V) { [void]$Candidates.Add($V) }
        }
        catch { }
    }
    if ($env:ProgramFiles) { [void]$Candidates.Add((Join-Path $env:ProgramFiles 'obs-studio')) }
    foreach ($C in $Candidates) {
        if ($C -and (Test-Path -LiteralPath (Join-Path $C 'bin\64bit\obs64.exe'))) { return (Resolve-Path -LiteralPath $C).Path }
    }
    return $null
}

function Get-ForgeObsVersion {
    param([string]$ObsDir)
    if (-not $ObsDir) { return $null }
    try {
        $V = (Get-Item -LiteralPath (Join-Path $ObsDir 'bin\64bit\obs64.exe')).VersionInfo.ProductVersion
        if ($V -match '^(\d+)\.(\d+)(?:\.(\d+))?') {
            $Patch = 0
            if ($Matches[3]) { $Patch = [int]$Matches[3] }
            return New-Object System.Version ([int]$Matches[1]), ([int]$Matches[2]), $Patch
        }
    }
    catch { }
    return $null
}

function ConvertFrom-ForgeIniText {
    <# Parses INI text into an ordered dictionary of ordered dictionaries. #>
    param([string]$Text)
    $Result = [ordered]@{}
    $Section = $null
    foreach ($Line in ($Text -split "`r?`n")) {
        $L = $Line.Trim([char]0xFEFF).Trim()
        if (-not $L -or $L.StartsWith(';') -or $L.StartsWith('#')) { continue }
        if ($L -match '^\[(.+)\]$') {
            $Section = $Matches[1]
            if (-not $Result.Contains($Section)) { $Result[$Section] = [ordered]@{} }
            continue
        }
        $Eq = $L.IndexOf('=')
        if ($Eq -lt 1) { continue }
        if ($null -eq $Section) { $Section = ''; if (-not $Result.Contains('')) { $Result[''] = [ordered]@{} } }
        $Result[$Section][$L.Substring(0, $Eq)] = $L.Substring($Eq + 1)
    }
    return $Result
}

function Invoke-ForgeProbeExe {
    param([string]$Exe, [string]$WorkDir)
    if (-not (Test-Path -LiteralPath $Exe)) { return $null }
    try {
        $Psi = New-Object System.Diagnostics.ProcessStartInfo
        $Psi.FileName = $Exe
        $Psi.WorkingDirectory = $WorkDir
        $Psi.UseShellExecute = $false
        $Psi.RedirectStandardOutput = $true
        $Psi.RedirectStandardError = $true
        $Psi.CreateNoWindow = $true
        $P = [System.Diagnostics.Process]::Start($Psi)
        $Out = $P.StandardOutput.ReadToEndAsync()
        if (-not $P.WaitForExit(20000)) { try { $P.Kill() } catch { }; return $null }
        return ConvertFrom-ForgeIniText $Out.Result
    }
    catch { return $null }
}

function Get-ForgeGpuNames {
    try { return @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | ForEach-Object { $_.Name } | Where-Object { $_ }) }
    catch { return @() }
}

function Get-ForgeCaps {
    <#
    Hardware encoder capabilities. Uses OBS's own probes (obs-nvenc-test.exe,
    obs-amf-test.exe, obs-qsv-test.exe in bin\64bit) - the same check OBS runs at startup.
    Without OBS, falls back to GPU names from WMI (Source = 'gpu-name').
    #>
    param([string]$ObsDir, [switch]$NoProbe)
    $Caps = [ordered]@{
        Source = 'none'
        Gpus = @(Get-ForgeGpuNames)
        nvenc = @{ Ok = $false; Hevc = $false; HevcBframes = 0; H264Bframes = 0 }
        amf = @{ Ok = $false; Hevc = $false }
        qsv = @{ Ok = $false; Hevc = $false }
    }
    $Bin = $null
    if ($ObsDir) { $Bin = Join-Path $ObsDir 'bin\64bit' }

    if ($Bin -and -not $NoProbe -and (Test-Path -LiteralPath $Bin)) {
        $Ran = $false
        $N = Invoke-ForgeProbeExe (Join-Path $Bin 'obs-nvenc-test.exe') $Bin
        if ($N) {
            $Ran = $true
            if ($N.Contains('general') -and $N['general']['nvenc_supported'] -eq 'true' -and
                $N.Contains('h264') -and $N['h264']['codec_supported'] -eq '1') {
                $Caps.nvenc.Ok = $true
                $Caps.nvenc.H264Bframes = [int]$N['h264']['bframes']
                if ($N.Contains('hevc') -and $N['hevc']['codec_supported'] -eq '1') {
                    $Caps.nvenc.Hevc = $true
                    $Caps.nvenc.HevcBframes = [int]$N['hevc']['bframes']
                }
            }
        }
        $A = Invoke-ForgeProbeExe (Join-Path $Bin 'obs-amf-test.exe') $Bin
        if ($A) {
            $Ran = $true
            foreach ($Sec in $A.Keys) {
                if ($A[$Sec]['is_amd'] -eq 'true' -and $A[$Sec]['supports_avc'] -eq 'true') {
                    $Caps.amf.Ok = $true
                    if ($A[$Sec]['supports_hevc'] -eq 'true') { $Caps.amf.Hevc = $true }
                }
            }
        }
        $Q = Invoke-ForgeProbeExe (Join-Path $Bin 'obs-qsv-test.exe') $Bin
        if ($Q) {
            $Ran = $true
            foreach ($Sec in $Q.Keys) {
                if ($Q[$Sec]['is_intel'] -eq 'true') {
                    $Caps.qsv.Ok = $true
                    if ($Q[$Sec]['supports_hevc'] -eq 'true') { $Caps.qsv.Hevc = $true }
                }
            }
        }
        if ($Ran) { $Caps.Source = 'obs-probe' }
    }

    if ($Caps.Source -eq 'none' -and $Caps.Gpus.Count -gt 0) {
        # Name fallback: assume the codecs every encoder of the last ~8 years supports.
        $Caps.Source = 'gpu-name'
        foreach ($G in $Caps.Gpus) {
            if ($G -match 'NVIDIA|GeForce|Quadro|RTX|GTX') { $Caps.nvenc = @{ Ok = $true; Hevc = $true; HevcBframes = 0; H264Bframes = 2 } }
            elseif ($G -match 'AMD|Radeon') { $Caps.amf = @{ Ok = $true; Hevc = $true } }
            elseif ($G -match 'Intel.*(Arc|UHD|Iris|Xe)') { $Caps.qsv = @{ Ok = $true; Hevc = $true } }
        }
    }
    return $Caps
}

function Select-ForgeEncoder {
    <# Best available family: NVENC, then AMF, then Quick Sync, then x264. #>
    param($Caps)
    foreach ($F in 'nvenc', 'amf', 'qsv') { if ($Caps[$F].Ok) { return $F } }
    return 'x264'
}

function Test-ForgeEncoderAvailable {
    param([string]$Family, $Caps)
    if ($Family -eq 'x264') { return $true }
    if ($Caps.Source -eq 'none') { return $null }   # unknown
    return [bool]$Caps[$Family].Ok
}

# --------------------------------------------------------------------------------------
# Encoder settings (per family, per codec)
# --------------------------------------------------------------------------------------

function Get-ForgeStreamPlan {
    <# Codec, encoder id and bitrate for a preset on a family. #>
    param($Preset, [string]$Family, $Caps)
    $F = $script:Families[$Family]
    $Codec = $Preset.StreamCodec
    $Kbps = $Preset.StreamKbps
    if ($Codec -eq 'hevc') {
        $HevcOk = $true
        if ($Family -eq 'x264') { $HevcOk = $false }
        elseif ($Caps -and $Caps.Source -ne 'none' -and $Caps[$Family].Ok -and -not $Caps[$Family].Hevc) { $HevcOk = $false }
        if (-not $HevcOk) { $Codec = 'h264'; $Kbps = $Preset.H264Kbps }
    }
    $Id = $F.H264
    if ($Codec -eq 'hevc') { $Id = $F.Hevc }
    return @{ Codec = $Codec; Id = $Id; Kbps = $Kbps }
}

function Get-ForgeRecordPlan {
    param($Preset, [string]$Family, $Caps)
    $F = $script:Families[$Family]
    if ($Family -eq 'x264' -and $Preset.Record -eq 'light') {
        # No hardware encoder: a second x264 session would eat the CPU the game needs, so
        # recording shares the stream encoder.
        return @{ Codec = 'h264'; Id = 'none'; Shared = $true }
    }
    $Codec = 'hevc'
    if (-not $F.Hevc) { $Codec = 'h264' }
    elseif ($Caps -and $Caps.Source -ne 'none' -and $Caps[$Family].Ok -and -not $Caps[$Family].Hevc) { $Codec = 'h264' }
    $Id = $F.H264
    if ($Codec -eq 'hevc') { $Id = $F.Hevc }
    return @{ Codec = $Codec; Id = $Id; Shared = $false }
}

function New-ForgeStreamSettings {
    param([string]$Family, $Plan, $Caps)
    $EncProfile = 'high'
    if ($Plan.Codec -eq 'hevc') { $EncProfile = 'main' }   # 8-bit; never main10 on an SDR canvas
    switch ($Family) {
        'nvenc' {
            $Bf = 2
            if ($Plan.Codec -eq 'hevc') {
                # HEVC B-frames need Turing or newer; the probe says how many this GPU has.
                $Bf = 0
                if ($Caps -and $Caps.nvenc.HevcBframes -ge 2) { $Bf = 2 }
            }
            return [ordered]@{
                rate_control = 'CBR'; bitrate = $Plan.Kbps; keyint_sec = 2; preset = 'p5'; tune = 'hq'
                multipass = 'disabled'; profile = $EncProfile; bf = $Bf; lookahead = $false; adaptive_quantization = $true
            }
        }
        'amf' {
            return [ordered]@{ rate_control = 'CBR'; bitrate = $Plan.Kbps; keyint_sec = 2; preset = 'quality'; profile = $EncProfile }
        }
        'qsv' {
            return [ordered]@{ rate_control = 'CBR'; bitrate = $Plan.Kbps; keyint_sec = 2; target_usage = 'TU2'; profile = $EncProfile }
        }
        'x264' {
            return [ordered]@{ rate_control = 'CBR'; bitrate = $Plan.Kbps; keyint_sec = 2; preset = 'veryfast'; profile = 'high'; tune = '' }
        }
    }
}

function New-ForgeRecordSettings {
    param([string]$Family, $Plan, [string]$Mode, $Caps)
    if ($Plan.Shared) { return $null }
    $EncProfile = 'high'
    if ($Plan.Codec -eq 'hevc') { $EncProfile = 'main' }
    $Quality = ($Mode -eq 'quality')
    $Cq = 22
    if ($Quality) { $Cq = 18 }
    switch ($Family) {
        'nvenc' {
            $NvPreset = 'p4'; $Bf = 0
            if ($Quality) {
                $NvPreset = 'p5'
                $Have = 2
                if ($Caps -and $Caps.Source -ne 'none') {
                    if ($Plan.Codec -eq 'hevc') { $Have = $Caps.nvenc.HevcBframes } else { $Have = $Caps.nvenc.H264Bframes }
                }
                elseif ($Plan.Codec -eq 'hevc') { $Have = 0 }
                if ($Have -ge 2) { $Bf = 2 }
            }
            return [ordered]@{
                rate_control = 'CQP'; cqp = $Cq; keyint_sec = 2; preset = $NvPreset; tune = 'hq'
                multipass = 'qres'; profile = $EncProfile; bf = $Bf; lookahead = $false; adaptive_quantization = $true
            }
        }
        'amf' {
            $P = 'balanced'
            if ($Quality) { $P = 'quality' }
            return [ordered]@{ rate_control = 'CQP'; cqp = $Cq; keyint_sec = 2; preset = $P; profile = $EncProfile }
        }
        'qsv' {
            $Tu = 'TU4'
            if ($Quality) { $Tu = 'TU2' }
            return [ordered]@{ rate_control = 'CQP'; cqp = $Cq; keyint_sec = 2; target_usage = $Tu; profile = $EncProfile }
        }
        'x264' {
            return [ordered]@{ rate_control = 'CRF'; crf = $Cq; keyint_sec = 2; preset = 'veryfast'; profile = 'high'; tune = '' }
        }
    }
}

# --------------------------------------------------------------------------------------
# basic.ini
# --------------------------------------------------------------------------------------

# Keys the user may change in OBS and that an upgrade must not reset. Everything else in
# the template is re-applied on install/upgrade (video, encoders, recording format).
$script:SoftKeys = @(
    'Output/FilenameFormatting', 'Output/DelayEnable', 'Output/DelaySec', 'Output/DelayPreserve',
    'Output/Reconnect', 'Output/RetryDelay', 'Output/MaxRetries', 'Output/BindIP', 'Output/IPFamily',
    'Output/NewSocketLoopEnable', 'Output/LowLatencyEnable', 'Output/DynamicBitrate',
    'Stream1/*', 'Audio/*',
    'SimpleOutput/RecFormat2', 'SimpleOutput/Preset', 'SimpleOutput/NVENCPreset2', 'SimpleOutput/RecQuality',
    'SimpleOutput/RecRB', 'SimpleOutput/RecRBTime', 'SimpleOutput/RecRBSize', 'SimpleOutput/RecRBPrefix',
    'SimpleOutput/StreamAudioEncoder', 'SimpleOutput/RecAudioEncoder', 'SimpleOutput/RecTracks', 'SimpleOutput/UseAdvanced',
    'AdvOut/TrackIndex', 'AdvOut/VodTrackIndex', 'AdvOut/RecTracks', 'AdvOut/FLVTrack', 'AdvOut/StreamMultiTrackAudioMixes',
    'AdvOut/FFOutputToFile', 'AdvOut/FFExtension', 'AdvOut/Track1Bitrate', 'AdvOut/Track2Bitrate', 'AdvOut/Track3Bitrate',
    'AdvOut/Track4Bitrate', 'AdvOut/Track5Bitrate', 'AdvOut/Track6Bitrate', 'AdvOut/RecSplitFileTime',
    'AdvOut/RecSplitFileSize', 'AdvOut/RecRB', 'AdvOut/RecRBTime', 'AdvOut/RecRBSize', 'AdvOut/VodTrackEnabled'
)

function Test-ForgeSoftKey {
    param([string]$Section, [string]$Key)
    return ($script:SoftKeys -contains "$Section/$Key") -or ($script:SoftKeys -contains "$Section/*")
}

function New-ForgeBasicIni {
    <# Ordered template for one preset. Key order matches the 0.1.0 profiles. #>
    param($Preset, [string]$Family, $StreamPlan, $RecordPlan)
    $F = $script:Families[$Family]
    $SimpleStream = $F.Simple
    if ($StreamPlan.Codec -eq 'hevc') { $SimpleStream = $F.SimpleHevc }
    # Simple mode records with the H.264 variant of the family, as 0.1.0 did.
    $SimpleRec = $F.Simple

    $AdvOut = [ordered]@{
        ApplyServiceSettings = 'true'
        UseRescale = 'false'
    }
    if ($Preset.StreamRescale) {
        $AdvOut.UseRescale = 'true'
        $AdvOut.RescaleFilter = '2'            # OBS_SCALE_BICUBIC
        $AdvOut.RescaleRes = $Preset.StreamRescale
    }
    foreach ($Pair in @(
            @('TrackIndex', '1'), @('VodTrackIndex', '2'), @('Encoder', $StreamPlan.Id), @('RecType', 'Standard'),
            @('RecFormat2', 'hybrid_mp4'), @('RecUseRescale', 'false'), @('RecTracks', '13'), @('RecEncoder', $RecordPlan.Id),
            @('FLVTrack', '1'), @('StreamMultiTrackAudioMixes', '1'), @('FFOutputToFile', 'false'), @('FFExtension', 'mp4'),
            @('Track1Bitrate', '160'), @('Track2Bitrate', '160'), @('Track3Bitrate', '160'), @('Track4Bitrate', '160'),
            @('Track5Bitrate', '160'), @('Track6Bitrate', '160'), @('RecSplitFileTime', '15'), @('RecSplitFileSize', '2048'),
            @('RecRB', 'true'), @('RecRBTime', '60'), @('RecRBSize', '4096'), @('AudioEncoder', 'ffmpeg_aac'),
            @('RecAudioEncoder', 'ffmpeg_aac'), @('VodTrackEnabled', 'true'))) {
        $AdvOut[$Pair[0]] = $Pair[1]
    }

    return [ordered]@{
        General = [ordered]@{ Name = $Preset.Name }
        Output = [ordered]@{
            Mode = 'Advanced'; FilenameFormatting = '%CCYY-%MM-%DD %hh-%mm-%ss'; DelayEnable = 'false'; DelaySec = '20'
            DelayPreserve = 'true'; Reconnect = 'true'; RetryDelay = '2'; MaxRetries = '25'; BindIP = 'default'
            IPFamily = 'IPv4+IPv6'; NewSocketLoopEnable = 'false'; LowLatencyEnable = 'false'; DynamicBitrate = 'true'
        }
        Stream1 = [ordered]@{
            IgnoreRecommended = 'false'; EnableMultitrackVideo = 'false'
            MultitrackVideoMaximumAggregateBitrateAuto = 'true'; MultitrackVideoMaximumVideoTracksAuto = 'true'
        }
        SimpleOutput = [ordered]@{
            RecFormat2 = 'hybrid_mp4'; VBitrate = [string]$StreamPlan.Kbps; ABitrate = '160'; Preset = 'veryfast'
            NVENCPreset2 = 'p5'; RecQuality = 'Small'; RecRB = 'false'; RecRBTime = '20'; RecRBSize = '512'
            RecRBPrefix = 'Replay'; StreamAudioEncoder = 'aac'; RecAudioEncoder = 'aac'; RecTracks = '1'
            StreamEncoder = $SimpleStream; RecEncoder = $SimpleRec; UseAdvanced = 'false'
        }
        AdvOut = $AdvOut
        Video = [ordered]@{
            BaseCX = [string]$Preset.Width; BaseCY = [string]$Preset.Height
            OutputCX = [string]$Preset.Width; OutputCY = [string]$Preset.Height
            FPSType = '0'; FPSCommon = [string]$Preset.Fps; ScaleType = 'bicubic'
            ColorFormat = 'NV12'; ColorSpace = '709'; ColorRange = 'Partial'
            SdrWhiteLevel = '300'; HdrNominalPeakLevel = '1000'
        }
        Audio = [ordered]@{
            MonitoringDeviceId = 'default'; MonitoringDeviceName = 'Default'; SampleRate = '48000'
            ChannelSetup = 'Stereo'; MeterDecayRate = '23.53'; PeakMeterType = '0'
        }
    }
}

function Merge-ForgeIni {
    <#
    Applies the template onto an existing INI. Template keys win, except soft keys the
    user already has. Existing sections/keys the template does not know (hotkeys, plugin
    settings, RecFilePath, ...) are kept in place.
    #>
    param($Existing, $Template)
    $Out = [ordered]@{}
    if ($Existing) {
        foreach ($S in $Existing.Keys) {
            $Out[$S] = [ordered]@{}
            foreach ($K in $Existing[$S].Keys) { $Out[$S][$K] = $Existing[$S][$K] }
        }
    }
    foreach ($S in $Template.Keys) {
        if (-not $Out.Contains($S)) { $Out[$S] = [ordered]@{} }
        foreach ($K in $Template[$S].Keys) {
            if ($Out[$S].Contains($K) -and (Test-ForgeSoftKey $S $K)) { continue }
            $Out[$S][$K] = $Template[$S][$K]
        }
    }
    return $Out
}

function ConvertTo-ForgeIniText {
    param($Ini)
    $Sb = New-Object System.Text.StringBuilder
    $First = $true
    foreach ($S in $Ini.Keys) {
        if (-not $First) { [void]$Sb.Append("`r`n") }
        $First = $false
        if ($S -ne '') { [void]$Sb.Append("[$S]`r`n") }
        foreach ($K in $Ini[$S].Keys) { [void]$Sb.Append("$K=$($Ini[$S][$K])`r`n") }
    }
    return $Sb.ToString()
}

function ConvertTo-ForgeJson {
    <# 4-space indented JSON for flat encoder settings, same layout OBS writes. #>
    param($Map)
    $Lines = foreach ($K in $Map.Keys) {
        $V = $Map[$K]
        if ($V -is [bool]) { $J = $V.ToString().ToLowerInvariant() }
        elseif ($V -is [int] -or $V -is [long] -or $V -is [double]) { $J = [string]$V }
        else { $J = '"' + ([string]$V).Replace('\', '\\').Replace('"', '\"') + '"' }
        '    "{0}": {1}' -f $K, $J
    }
    return "{`r`n" + ($Lines -join ",`r`n") + "`r`n}`r`n"
}

function Write-ForgeText {
    param([string]$Path, [string]$Text, [switch]$Bom)
    $Enc = $script:Utf8NoBom
    if ($Bom) { $Enc = $script:Utf8Bom }
    # Write to a temp file in the same folder, then move: a crash never leaves half a file.
    $Tmp = "$Path.forge-tmp"
    [System.IO.File]::WriteAllText($Tmp, $Text, $Enc)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Move-Item -LiteralPath $Tmp -Destination $Path
}

# --------------------------------------------------------------------------------------
# Profile build / install state
# --------------------------------------------------------------------------------------

function Get-ForgeProfileBuild {
    <# Everything one profile needs, without touching disk. #>
    param($Preset, [string]$Family, $Caps)
    $StreamPlan = Get-ForgeStreamPlan $Preset $Family $Caps
    $RecordPlan = Get-ForgeRecordPlan $Preset $Family $Caps
    $Marker = [ordered]@{
        pack = 'OBS-Forge'; version = $script:PackVersion; preset = $Preset.Id; encoder = $Family
        width = $Preset.Width; height = $Preset.Height; fps = $Preset.Fps
        streamEncoder = $StreamPlan.Id; streamCodec = $StreamPlan.Codec; streamKbps = $StreamPlan.Kbps
        recordEncoder = $RecordPlan.Id; recordCodec = $RecordPlan.Codec; record = $Preset.Record
        capsSource = $Caps.Source
    }
    return @{
        Preset = $Preset; Family = $Family
        StreamPlan = $StreamPlan; RecordPlan = $RecordPlan
        Ini = New-ForgeBasicIni $Preset $Family $StreamPlan $RecordPlan
        Stream = New-ForgeStreamSettings $Family $StreamPlan $Caps
        Record = New-ForgeRecordSettings $Family $RecordPlan $Preset.Record $Caps
        Marker = $Marker
    }
}

function Get-ForgeInstalledProfile {
    <# OBS-Forge profiles in a config root: marker file or a 0.1.0 legacy name. #>
    param([string]$ConfigRoot)
    $Dir = Join-Path $ConfigRoot 'basic\profiles'
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    $Found = foreach ($D in Get-ChildItem -LiteralPath $Dir -Directory) {
        $MarkerPath = Join-Path $D.FullName $script:MarkerName
        if (Test-Path -LiteralPath $MarkerPath) {
            $M = $null
            try { $M = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json } catch { }
            if ($M -and $M.pack -eq 'OBS-Forge') {
                [pscustomobject]@{ Name = $D.Name; Path = $D.FullName; Version = [string]$M.version; Preset = [string]$M.preset; Marker = $M; Legacy = $false }
                continue
            }
        }
        if ($script:LegacyProfiles.ContainsKey($D.Name) -and (Test-Path -LiteralPath (Join-Path $D.FullName 'basic.ini'))) {
            [pscustomobject]@{ Name = $D.Name; Path = $D.FullName; Version = '0.1.0'; Preset = $script:LegacyProfiles[$D.Name]; Marker = $null; Legacy = $true }
        }
    }
    return @($Found)
}

function Compare-ForgeVersion {
    param([string]$A, [string]$B)
    try { return ([version]$A).CompareTo([version]$B) } catch { return [string]::Compare($A, $B) }
}

function New-ForgeBackupDir {
    <# backups\<stamp> in the pack folder; falls back to %LOCALAPPDATA% when it is read-only. #>
    param([string]$Prefix = '')
    $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Bases = @((Join-Path $script:PackRoot 'backups'), (Join-Path $env:LOCALAPPDATA 'OBS-Forge\backups'))
    # Tests (and anyone who wants backups elsewhere) can point this at another folder.
    if ($env:OBSFORGE_BACKUP_ROOT) { $Bases = @($env:OBSFORGE_BACKUP_ROOT) + $Bases }
    foreach ($Base in $Bases) {
        try {
            $Dir = Join-Path $Base "$Prefix$Stamp"
            $N = 1
            while (Test-Path -LiteralPath $Dir) { $Dir = Join-Path $Base "$Prefix$Stamp-$N"; $N++ }
            New-Item -ItemType Directory -Force -Path $Dir -ErrorAction Stop | Out-Null
            return $Dir
        }
        catch { }
    }
    throw 'Could not create a backup folder (pack folder and %LOCALAPPDATA% are both read-only).'
}

function Install-ForgeProfile {
    <#
    Installs or upgrades one profile. Returns @{ Name; Action; Reason }.
      new folder             -> installed
      ours, older version    -> upgraded (service.json, hotkeys and other user keys kept)
      ours, other encoder    -> reapplied
      ours, same version     -> skipped unless -Force
      someone else's folder  -> skipped unless -Force
    #>
    param([string]$ConfigRoot, $Build, [switch]$Force, [scriptblock]$GetBackupDir)
    $Name = $Build.Preset.Name
    $Dest = Join-Path $ConfigRoot "basic\profiles\$Name"
    $Existing = Get-ForgeInstalledProfile $ConfigRoot | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    $Action = 'installed'; $Reason = ''

    if (Test-Path -LiteralPath $Dest) {
        if ($Existing) {
            $Cmp = Compare-ForgeVersion $Existing.Version $script:PackVersion
            $OldEncoder = ''
            if ($Existing.Marker) { $OldEncoder = [string]$Existing.Marker.encoder }
            if ($Cmp -lt 0) { $Action = 'upgraded'; $Reason = "from $($Existing.Version)" }
            elseif ($OldEncoder -and $OldEncoder -ne $Build.Family) { $Action = 'reapplied'; $Reason = "encoder $OldEncoder -> $($Build.Family)" }
            elseif ($Force) { $Action = 'reapplied'; $Reason = '-Force' }
            else { return @{ Name = $Name; Action = 'skipped'; Reason = "already $($Existing.Version) (use -Force to re-apply)" } }
        }
        elseif ($Force) { $Action = 'reapplied'; $Reason = 'not an OBS-Forge profile, -Force' }
        else { return @{ Name = $Name; Action = 'skipped'; Reason = 'a profile with this name exists and is not OBS-Forge (use -Force)' } }

        $Backup = & $GetBackupDir
        Copy-Item -LiteralPath $Dest -Destination (Join-Path $Backup $Name) -Recurse -Force
    }
    else {
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    }

    $IniPath = Join-Path $Dest 'basic.ini'
    $Current = $null
    if (Test-Path -LiteralPath $IniPath) { $Current = ConvertFrom-ForgeIniText ([System.IO.File]::ReadAllText($IniPath)) }
    $Merged = Merge-ForgeIni $Current $Build.Ini
    if ($Build.RecordPlan.Shared) {
        # Recording shares the stream encoder; a stale recordEncoder.json would confuse Verify.
        $RecJson = Join-Path $Dest 'recordEncoder.json'
        if (Test-Path -LiteralPath $RecJson) { Remove-Item -LiteralPath $RecJson -Force }
    }
    if (-not $Build.Preset.StreamRescale -and $Merged.Contains('AdvOut')) {
        # Same preset never had rescale; drop leftovers from a hand edit only if UseRescale is off.
        if ($Merged['AdvOut']['UseRescale'] -eq 'false') { [void]$Merged['AdvOut'].Remove('RescaleRes') }
    }

    Write-ForgeText $IniPath (ConvertTo-ForgeIniText $Merged) -Bom
    Write-ForgeText (Join-Path $Dest 'streamEncoder.json') (ConvertTo-ForgeJson $Build.Stream)
    if ($Build.Record) { Write-ForgeText (Join-Path $Dest 'recordEncoder.json') (ConvertTo-ForgeJson $Build.Record) }
    $Marker = $Build.Marker
    $Marker.installed = (Get-Date).ToString('s')
    Write-ForgeText (Join-Path $Dest $script:MarkerName) (($Marker | ConvertTo-Json) + "`r`n")
    return @{ Name = $Name; Action = $Action; Reason = $Reason }
}

# --------------------------------------------------------------------------------------
# Scene collections
# --------------------------------------------------------------------------------------

function New-ForgeUuid {
    <# Deterministic UUID so regenerating a collection gives identical files. #>
    param([string]$Seed)
    $Md5 = [System.Security.Cryptography.MD5]::Create()
    $B = $Md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("OBS-Forge/$Seed"))
    $B[6] = ($B[6] -band 0x0F) -bor 0x30
    $B[8] = ($B[8] -band 0x3F) -bor 0x80
    $H = -join ($B | ForEach-Object { $_.ToString('x2') })
    return '{0}-{1}-{2}-{3}-{4}' -f $H.Substring(0, 8), $H.Substring(8, 4), $H.Substring(12, 4), $H.Substring(16, 4), $H.Substring(20, 12)
}

function New-ForgeSource {
    param([string]$Collection, [string]$Name, [string]$Id, $Settings, [int]$Mixers = 0, [string]$Versioned)
    if (-not $Versioned) { $Versioned = $Id }
    return [ordered]@{
        prev_ver = 553648130   # 33.0.2
        name = $Name; uuid = (New-ForgeUuid "$Collection/$Name"); id = $Id; versioned_id = $Versioned
        settings = $Settings; mixers = $Mixers; sync = 0; flags = 0; volume = 1.0; balance = 0.5
        enabled = $true; muted = $false
        'push-to-mute' = $false; 'push-to-mute-delay' = 0; 'push-to-talk' = $false; 'push-to-talk-delay' = 0
        hotkeys = [ordered]@{}; deinterlace_mode = 0; deinterlace_field_order = 0
        monitoring_type = 0; monitoring_enabled = $false; private_settings = [ordered]@{}
    }
}

function New-ForgeItem {
    <#
    Scene item with both absolute (pos/scale/bounds) and relative (pos_rel/scale_rel/
    bounds_rel) coordinates. OBS 32+ uses the relative set, which follows the canvas size
    (libobs/obs-scene.c pos_from_absolute/size_from_absolute); older OBS uses the absolute.
    #>
    param($Source, [int]$ItemId, [int]$W, [int]$H, [double]$X, [double]$Y, [int]$Align,
        [int]$BoundsType = 0, [double]$BoundsX = 0, [double]$BoundsY = 0, [int]$BoundsAlign = 0)
    $Rel = { param($v) [math]::Round($v, 7) }
    return [ordered]@{
        name = $Source.name; source_uuid = $Source.uuid; visible = $true; locked = $false; rot = 0.0
        scale_ref = [ordered]@{ x = [double]$W; y = [double]$H }
        align = $Align; bounds_type = $BoundsType; bounds_align = $BoundsAlign; bounds_crop = $false
        crop_left = 0; crop_top = 0; crop_right = 0; crop_bottom = 0; id = $ItemId; group_item_backup = $false
        pos = [ordered]@{ x = $X; y = $Y }
        pos_rel = [ordered]@{ x = (& $Rel ((2 * $X - $W) / $H)); y = (& $Rel ((2 * $Y / $H) - 1)) }
        scale = [ordered]@{ x = 1.0; y = 1.0 }
        scale_rel = [ordered]@{ x = 1.0; y = 1.0 }
        bounds = [ordered]@{ x = $BoundsX; y = $BoundsY }
        bounds_rel = [ordered]@{ x = (& $Rel (2 * $BoundsX / $H)); y = (& $Rel (2 * $BoundsY / $H)) }
        scale_filter = 'disable'; blend_method = 'default'; blend_type = 'normal'
        show_transition = [ordered]@{ duration = 300 }; hide_transition = [ordered]@{ duration = 300 }
        private_settings = [ordered]@{}
    }
}

function New-ForgeAudioDevice {
    param([string]$Collection, [string]$Kind)
    if ($Kind -eq 'desktop') {
        return New-ForgeSource $Collection 'Desktop Audio' 'wasapi_output_capture' ([ordered]@{ device_id = 'default' }) 255
    }
    return New-ForgeSource $Collection 'Mic/Aux' 'wasapi_input_capture' ([ordered]@{ device_id = 'default' }) 255
}

function New-ForgeCollection {
    <#
    Generic collection: Starting Soon, Live (Game Capture, any fullscreen app), BRB, Ending,
    plus the default Desktop Audio and Mic/Aux devices. No URLs, no local paths.
    #>
    param([string]$Name, [int]$Width, [int]$Height)
    $Sources = New-Object System.Collections.ArrayList
    $Scenes = New-Object System.Collections.ArrayList
    $Bg = 4279177493     # 0xFF0F0F15, near-black
    $FontSize = [int][math]::Round(120 * [math]::Min($Width, $Height) / 1080)

    foreach ($Scene in @('Starting Soon', 'Live', 'BRB', 'Ending')) {
        $Items = New-Object System.Collections.ArrayList
        $BgSrc = New-ForgeSource $Name "$Scene Background" 'color_source' ([ordered]@{ color = $Bg; width = $Width; height = $Height })
        [void]$Sources.Add($BgSrc)
        # Background stretched to the canvas (bounds_type 1 = OBS_BOUNDS_STRETCH).
        [void]$Items.Add((New-ForgeItem $BgSrc 1 $Width $Height 0 0 5 1 $Width $Height 0))
        if ($Scene -eq 'Live') {
            $Game = New-ForgeSource $Name 'Game Capture' 'game_capture' ([ordered]@{ capture_mode = 'any_fullscreen'; capture_cursor = $true })
            [void]$Sources.Add($Game)
            # Fit any game resolution inside the canvas (bounds_type 2 = OBS_BOUNDS_SCALE_INNER).
            [void]$Items.Add((New-ForgeItem $Game 2 $Width $Height 0 0 5 2 $Width $Height 0))
        }
        else {
            $Text = New-ForgeSource $Name "$Scene Text" 'text_gdiplus' ([ordered]@{
                    # flags 1 = OBS_FONT_BOLD; the style string alone does not make it bold.
                    text = $Scene; font = [ordered]@{ face = 'Arial'; style = 'Bold'; size = $FontSize; flags = 1 }
                    color = 4294967295; bg_color = 0; outline = $false; outline_color = 0; outline_size = 0
                    shadow = $false; align = 1; valign = 1; transform = 0; read_from_file = $false; wrap = $false
                }) 0 'text_gdiplus_v2'
            [void]$Sources.Add($Text)
            # Centred: item origin at its centre (align 0) placed in the middle of the canvas.
            [void]$Items.Add((New-ForgeItem $Text 2 $Width $Height ($Width / 2) ($Height / 2) 0))
        }
        $SceneSrc = New-ForgeSource $Name $Scene 'scene' ([ordered]@{ id_counter = $Items.Count + 1; custom_size = $false; items = @($Items) })
        [void]$Scenes.Add($SceneSrc)
    }
    foreach ($S in $Scenes) { [void]$Sources.Add($S) }

    $Doc = [ordered]@{
        name = $Name
        DesktopAudioDevice1 = (New-ForgeAudioDevice $Name 'desktop')
        AuxAudioDevice1 = (New-ForgeAudioDevice $Name 'mic')
        sources = @($Sources)
        groups = @()
        scene_order = @('Starting Soon', 'Live', 'BRB', 'Ending' | ForEach-Object { [ordered]@{ name = $_ } })
        current_scene = 'Live'; current_program_scene = 'Live'
        canvases = @()
        current_transition = 'Fade'; transition_duration = 300; transitions = @()
        quick_transitions = @(
            [ordered]@{ name = 'Cut'; duration = 300; hotkeys = @(); id = 1; fade_to_black = $false }
            [ordered]@{ name = 'Fade'; duration = 300; hotkeys = @(); id = 2; fade_to_black = $false }
            [ordered]@{ name = 'Fade'; duration = 300; hotkeys = @(); id = 3; fade_to_black = $true }
        )
        saved_projectors = @(); preview_locked = $false
        scaling_enabled = $false; scaling_level = 0; scaling_off_x = 0.0; scaling_off_y = 0.0
        'virtual-camera' = [ordered]@{ type2 = 3 }
        modules = [ordered]@{}
        version = 2
    }
    return ($Doc | ConvertTo-Json -Depth 32)
}

function Get-ForgeCollectionSize {
    <# Canvas a collection is laid out for: the first preset that names it. #>
    param([string]$Collection)
    $P = Get-ForgePreset | Where-Object { $_.Collection -eq $Collection } | Select-Object -First 1
    if ($P) { return @{ Width = $P.Width; Height = $P.Height } }
    return @{ Width = 1920; Height = 1080 }
}

function Add-ForgeMissingAudio {
    <#
    0.1.0 collections had no global audio devices, so OBS loaded them silent. Adds Desktop
    Audio / Mic/Aux to an existing collection without touching its scenes. Returns $true
    when the file changed.
    #>
    param([string]$Path, [string]$Collection)
    $Text = [System.IO.File]::ReadAllText($Path)
    $Add = New-Object System.Collections.ArrayList
    if ($Text -notmatch '"DesktopAudioDevice1"\s*:') { [void]$Add.Add('"DesktopAudioDevice1": ' + ((New-ForgeAudioDevice $Collection 'desktop') | ConvertTo-Json -Depth 8)) }
    if ($Text -notmatch '"AuxAudioDevice1"\s*:') { [void]$Add.Add('"AuxAudioDevice1": ' + ((New-ForgeAudioDevice $Collection 'mic') | ConvertTo-Json -Depth 8)) }
    if ($Add.Count -eq 0) { return $false }
    $Brace = $Text.IndexOf('{')
    if ($Brace -lt 0) { return $false }
    $New = $Text.Substring(0, $Brace + 1) + "`r`n" + ($Add -join ",`r`n") + ',' + $Text.Substring($Brace + 1)
    # Parse check before writing: never leave OBS a collection it cannot read.
    $null = $New | ConvertFrom-Json
    Write-ForgeText $Path $New
    return $true
}

Export-ModuleMember -Function *-Forge*
