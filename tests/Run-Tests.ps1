#requires -Version 5.1
<#
OBS-Forge test suite. No dependencies; runs under Windows PowerShell 5.1 and PowerShell 7.

    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
    pwsh -NoProfile -File tests/Run-Tests.ps1

Every install/verify/uninstall runs the real script in a child process of the same
PowerShell edition against a throw-away config root, so exit codes are tested too.
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Fixtures = Join-Path $PSScriptRoot 'fixtures\v0.1.0'
Import-Module (Join-Path $Root 'lib\OBSForge.psm1') -Force

$Host_ = (Get-Process -Id $PID).Path
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("obsforge-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$env:OBSFORGE_BACKUP_ROOT = Join-Path $Work 'backups'

$script:Pass = 0
$script:Failures = New-Object System.Collections.ArrayList
$script:Current = ''

function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:Current = $Name
    try { & $Body }
    catch { [void]$script:Failures.Add("$Name :: threw: $($_.Exception.Message)") }
}
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { $script:Pass++ } else { [void]$script:Failures.Add("$($script:Current) :: $Msg") }
}
function AssertEq($Expected, $Actual, [string]$Msg) {
    Assert ("$Expected" -eq "$Actual") "$Msg (expected '$Expected', got '$Actual')"
}
function New-Root([string]$Name) {
    $R = Join-Path $Work $Name
    New-Item -ItemType Directory -Force -Path $R | Out-Null
    return $R
}
function Invoke-Script([string]$Script, [string[]]$Arguments) {
    $Args_ = @('-NoProfile', '-NonInteractive')
    if ($Host_ -match 'powershell\.exe$') { $Args_ += @('-ExecutionPolicy', 'Bypass') }
    $Args_ += @('-File', (Join-Path $Root $Script)) + $Arguments
    $Out = & $Host_ @Args_ 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = $Out }
}
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Read-Ini([string]$Path) { ConvertFrom-ForgeIniText ([System.IO.File]::ReadAllText($Path)) }
function Norm([string]$T) { return ($T.TrimStart([char]0xFEFF) -replace "`r`n", "`n").TrimEnd() }

# A probe result like an RTX 40 card, so builds are deterministic on any machine.
$CapsNv = [ordered]@{ Source = 'obs-probe'; Gpus = @('Test GPU')
    nvenc = @{ Ok = $true; Hevc = $true; HevcBframes = 5; H264Bframes = 7 }
    amf = @{ Ok = $false; Hevc = $false }; qsv = @{ Ok = $false; Hevc = $false } }
$CapsNoHevc = [ordered]@{ Source = 'obs-probe'; Gpus = @('Old GPU')
    nvenc = @{ Ok = $true; Hevc = $false; HevcBframes = 0; H264Bframes = 0 }
    amf = @{ Ok = $false; Hevc = $false }; qsv = @{ Ok = $false; Hevc = $false } }
$CapsNone = [ordered]@{ Source = 'none'; Gpus = @()
    nvenc = @{ Ok = $false; Hevc = $false; HevcBframes = 0; H264Bframes = 0 }
    amf = @{ Ok = $false; Hevc = $false }; qsv = @{ Ok = $false; Hevc = $false } }

# ---------------------------------------------------------------------------------------
Test-Case 'preset catalogue is valid' {
    $All = @(Get-ForgePreset)
    Assert ($All.Count -ge 9) "expected at least 9 presets, got $($All.Count)"
    AssertEq $All.Count (@($All | ForEach-Object { $_.Id } | Select-Object -Unique)).Count 'preset ids are unique'
    AssertEq $All.Count (@($All | ForEach-Object { $_.Name } | Select-Object -Unique)).Count 'preset names are unique'
    foreach ($P in $All) {
        Assert ($P.Name.StartsWith('OBS-Forge ')) "$($P.Id) name prefix"
        Assert (@(24, 25, 30, 48, 50, 60) -contains $P.Fps) "$($P.Id) fps $($P.Fps)"
        Assert (($P.Width % 2) -eq 0 -and ($P.Height % 2) -eq 0) "$($P.Id) even resolution"
        Assert (@('h264', 'hevc') -contains $P.StreamCodec) "$($P.Id) stream codec"
        Assert (@('light', 'quality') -contains $P.Record) "$($P.Id) record mode"
        Assert ($P.StreamKbps -ge 1000 -and $P.StreamKbps -le 51000) "$($P.Id) bitrate range"
        Assert ([bool]$P.Collection) "$($P.Id) collection"
    }
    AssertEq '1080p60,1080p30' ((Get-ForgePreset 'recommended' | ForEach-Object { $_.Id }) -join ',') 'recommended = the 0.1.0 pair'
    AssertEq '720p60,1080p60' ((Get-ForgePreset '720p60,OBS-Forge 1080p60,720p60' | ForEach-Object { $_.Id }) -join ',') 'ids, names, de-dup'
    $Threw = $false; try { Get-ForgePreset 'nope' | Out-Null } catch { $Threw = $true }
    Assert $Threw 'unknown preset throws'
}

Test-Case 'golden: 1080p60/1080p30 NVENC match 0.1.0 except the fixed keys' {
    foreach ($Id in '1080p60', '1080p30') {
        $P = Get-ForgePreset $Id
        $B = Get-ForgeProfileBuild $P 'nvenc' $CapsNv
        $Dir = Join-Path $Fixtures "profiles\$($P.Name)"
        AssertEq (Norm ([System.IO.File]::ReadAllText((Join-Path $Dir 'basic.ini')))) (Norm (ConvertTo-ForgeIniText $B.Ini)) "$Id basic.ini identical to 0.1.0"
        foreach ($Pair in @(@('streamEncoder.json', $B.Stream), @('recordEncoder.json', $B.Record))) {
            $Old = Read-Json (Join-Path $Dir $Pair[0])
            $New = (ConvertTo-ForgeJson $Pair[1]) | ConvertFrom-Json
            foreach ($Prop in $Old.PSObject.Properties) {
                $Key = $Prop.Name
                if ($Key -eq 'preset2') { $Key = 'preset' }
                if ($Key -eq 'psycho_aq') { $Key = 'adaptive_quantization' }
                AssertEq $Prop.Value $New.$Key "$Id $($Pair[0]) $($Prop.Name)->$Key"
            }
            Assert ($null -eq $New.PSObject.Properties['preset2']) "$Id $($Pair[0]) has no legacy preset2"
            Assert ($null -eq $New.PSObject.Properties['psycho_aq']) "$Id $($Pair[0]) has no legacy psycho_aq"
        }
    }
}

Test-Case 'every preset builds for every encoder family' {
    foreach ($P in Get-ForgePreset) {
        foreach ($F in 'nvenc', 'amf', 'qsv', 'x264') {
            $B = Get-ForgeProfileBuild $P $F $CapsNv
            AssertEq $P.Name $B.Ini['General']['Name'] "$($P.Id)/$F name"
            AssertEq 'NV12/709/Partial' ("{0}/{1}/{2}" -f $B.Ini['Video']['ColorFormat'], $B.Ini['Video']['ColorSpace'], $B.Ini['Video']['ColorRange']) "$($P.Id)/$F colour"
            AssertEq "$($P.Width)x$($P.Height)" ("{0}x{1}" -f $B.Ini['Video']['OutputCX'], $B.Ini['Video']['OutputCY']) "$($P.Id)/$F canvas"
            AssertEq $B.StreamPlan.Id $B.Ini['AdvOut']['Encoder'] "$($P.Id)/$F stream encoder id"
            AssertEq $B.RecordPlan.Id $B.Ini['AdvOut']['RecEncoder'] "$($P.Id)/$F record encoder id"
            AssertEq 'CBR' $B.Stream.rate_control "$($P.Id)/$F stream CBR"
            AssertEq 2 $B.Stream.keyint_sec "$($P.Id)/$F 2 s keyframes"
            Assert (-not ($B.Stream.Contains('preset2') -or $B.Stream.Contains('psycho_aq'))) "$($P.Id)/$F no legacy NVENC keys"
            Assert ("$($B.Stream.profile)" -notmatch '10') "$($P.Id)/$F stream 8-bit"
            if ($B.Record) { Assert ("$($B.Record.profile)" -notmatch '10') "$($P.Id)/$F record 8-bit" }
            if ($F -eq 'x264') {
                AssertEq 'obs_x264' $B.StreamPlan.Id "$($P.Id) x264 stream id"
                AssertEq 'h264' $B.StreamPlan.Codec "$($P.Id) x264 has no HEVC"
                AssertEq $P.H264Kbps $B.StreamPlan.Kbps "$($P.Id) x264 falls back to H264Kbps"
                if ($P.Record -eq 'light') { AssertEq 'none' $B.RecordPlan.Id "$($P.Id) x264 light recording shares the stream encoder"; Assert ($null -eq $B.Record) 'no record json' }
            }
            else {
                AssertEq $P.StreamCodec $B.StreamPlan.Codec "$($P.Id)/$F stream codec kept"
                AssertEq 'hevc' $B.RecordPlan.Codec "$($P.Id)/$F records HEVC"
            }
        }
    }
    $Ids = @{ nvenc = 'obs_nvenc_h264_tex'; amf = 'h264_texture_amf'; qsv = 'obs_qsv11_v2'; x264 = 'obs_x264' }
    foreach ($F in $Ids.Keys) { AssertEq $Ids[$F] (Get-ForgeProfileBuild (Get-ForgePreset '1080p60') $F $CapsNv).StreamPlan.Id "$F H.264 id" }
    $Yt = Get-ForgeProfileBuild (Get-ForgePreset 'youtube-1080p60') 'nvenc' $CapsNv
    AssertEq 'obs_nvenc_hevc_tex' $Yt.StreamPlan.Id 'YouTube streams HEVC on NVENC'
    AssertEq 'main' $Yt.Stream.profile 'YouTube HEVC is 8-bit main'
    AssertEq 2 $Yt.Stream.bf 'HEVC B-frames when the probe reports them'
    $Rec = Get-ForgeProfileBuild (Get-ForgePreset 'record-1440p60') 'nvenc' $CapsNv
    AssertEq 18 $Rec.Record.cqp 'record preset CQ 18'
    AssertEq 'p5' $Rec.Record.preset 'record preset p5'
    AssertEq '1920x1080' $Rec.Ini['AdvOut']['RescaleRes'] 'record-1440p60 streams at 1080p'
    AssertEq 'true' $Rec.Ini['AdvOut']['UseRescale'] 'rescale on'
}

Test-Case 'capability fallbacks' {
    $B = Get-ForgeProfileBuild (Get-ForgePreset 'youtube-1440p60') 'nvenc' $CapsNoHevc
    AssertEq 'h264' $B.StreamPlan.Codec 'no HEVC -> H.264 stream'
    AssertEq 34000 $B.StreamPlan.Kbps 'no HEVC -> H.264 bitrate'
    AssertEq 'obs_nvenc_h264_tex' $B.RecordPlan.Id 'no HEVC -> H.264 recording'
    $Q = Get-ForgeProfileBuild (Get-ForgePreset 'record-1080p60') 'nvenc' $CapsNoHevc
    AssertEq 0 $Q.Record.bf 'no B-frames when the probe reports none'
    $U = Get-ForgeProfileBuild (Get-ForgePreset 'record-1080p60') 'nvenc' $CapsNone
    AssertEq 0 $U.Record.bf 'unknown caps -> safe HEVC B-frames 0'
    AssertEq 'x264' (Select-ForgeEncoder $CapsNone) 'nothing detected -> x264'
    AssertEq 'nvenc' (Select-ForgeEncoder $CapsNv) 'NVENC first'
    $Amf = [ordered]@{ Source = 'obs-probe'; nvenc = @{ Ok = $false }; amf = @{ Ok = $true; Hevc = $true }; qsv = @{ Ok = $true; Hevc = $true } }
    AssertEq 'amf' (Select-ForgeEncoder $Amf) 'AMF before Quick Sync'
    AssertEq $false (Test-ForgeEncoderAvailable 'nvenc' $Amf) 'NVENC unavailable on AMD'
    AssertEq $true (Test-ForgeEncoderAvailable 'x264' $CapsNone) 'x264 always available'
}

Test-Case 'INI merge keeps user keys, hotkeys and soft settings' {
    $Existing = ConvertFrom-ForgeIniText "[General]`r`nName=X`r`n[Audio]`r`nMonitoringDeviceId=mine`r`n[Video]`r`nColorSpace=2100PQ`r`n[Hotkeys]`r`nOBSBasic.StartStreaming={""bindings"":[]}`r`n"
    $T = (Get-ForgeProfileBuild (Get-ForgePreset '1080p60') 'nvenc' $CapsNv).Ini
    $M = Merge-ForgeIni $Existing $T
    AssertEq 'mine' $M['Audio']['MonitoringDeviceId'] 'soft key kept'
    AssertEq '709' $M['Video']['ColorSpace'] 'enforced key re-applied'
    AssertEq 'OBS-Forge 1080p60' $M['General']['Name'] 'name enforced'
    Assert ($M.Contains('Hotkeys')) 'hotkeys section kept'
    $Round = ConvertFrom-ForgeIniText (ConvertTo-ForgeIniText $M)
    AssertEq '{"bindings":[]}' $Round['Hotkeys']['OBSBasic.StartStreaming'] 'hotkey value survives a round trip'
}

Test-Case 'scene collection: audio, game capture, centred labels, canvas-relative' {
    foreach ($Case in @(@('OBS-Forge', 1920, 1080), @('OBS-Forge Vertical', 1080, 1920))) {
        $J = (New-ForgeCollection $Case[0] $Case[1] $Case[2]) | ConvertFrom-Json
        AssertEq $Case[0] $J.name "$($Case[0]) name"
        AssertEq 'wasapi_output_capture' $J.DesktopAudioDevice1.id 'desktop audio device'
        AssertEq 'default' $J.DesktopAudioDevice1.settings.device_id 'desktop audio = default device'
        AssertEq 'wasapi_input_capture' $J.AuxAudioDevice1.id 'mic device'
        AssertEq 'Starting Soon,Live,BRB,Ending' (($J.scene_order | ForEach-Object { $_.name }) -join ',') 'scene order'
        $Uuids = @($J.sources | ForEach-Object { $_.uuid }) + $J.DesktopAudioDevice1.uuid + $J.AuxAudioDevice1.uuid
        AssertEq $Uuids.Count (@($Uuids | Select-Object -Unique)).Count 'unique uuids'
        $Live = $J.sources | Where-Object { $_.name -eq 'Live' }
        $GameItem = $Live.settings.items | Where-Object { $_.name -eq 'Game Capture' }
        Assert ($null -ne $GameItem) 'Live has Game Capture'
        AssertEq 2 $GameItem.bounds_type 'game capture fits the canvas'
        AssertEq 'any_fullscreen' ($J.sources | Where-Object { $_.name -eq 'Game Capture' }).settings.capture_mode 'captures any fullscreen app'
        foreach ($S in 'Starting Soon', 'BRB', 'Ending') {
            $Item = ($J.sources | Where-Object { $_.name -eq $S }).settings.items | Where-Object { $_.name -eq "$S Text" }
            AssertEq 0 $Item.align "$S label origin centred"
            AssertEq ($Case[1] / 2) $Item.pos.x "$S label x centre"
            AssertEq ($Case[2] / 2) $Item.pos.y "$S label y centre"
            Assert ([math]::Abs($Item.pos_rel.x) -lt 1e-6 -and [math]::Abs($Item.pos_rel.y) -lt 1e-6) "$S relative position is the centre"
        }
        $Bg = ($J.sources | Where-Object { $_.name -eq 'BRB' }).settings.items | Where-Object { $_.name -eq 'BRB Background' }
        AssertEq 1 $Bg.bounds_type 'background stretched'
        Assert ([math]::Abs($Bg.bounds_rel.y - 2) -lt 1e-6) 'background spans the canvas height'
        Assert ([math]::Abs($Bg.bounds_rel.x - (2.0 * $Case[1] / $Case[2])) -lt 1e-5) 'background spans the canvas width'
        Assert ((New-ForgeCollection $Case[0] $Case[1] $Case[2]) -eq (New-ForgeCollection $Case[0] $Case[1] $Case[2])) 'deterministic'
    }
}

Test-Case 'clean install, verify, re-run, force, encoder switch' {
    $R = New-Root 'clean'
    $I = Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'nvenc', '-IgnoreRunning')
    AssertEq 0 $I.Code "install exit`n$($I.Out)"
    foreach ($N in 'OBS-Forge 1080p60', 'OBS-Forge 1080p30') {
        $D = Join-Path $R "basic\profiles\$N"
        foreach ($F in 'basic.ini', 'streamEncoder.json', 'recordEncoder.json', 'obs-forge.json') { Assert (Test-Path -LiteralPath (Join-Path $D $F)) "$N/$F written" }
        AssertEq '0.2.0' (Read-Json (Join-Path $D 'obs-forge.json')).version "$N marker version"
        $Bytes = [System.IO.File]::ReadAllBytes((Join-Path $D 'basic.ini'))
        Assert ($Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) "$N basic.ini has the UTF-8 BOM OBS writes"
    }
    Assert (Test-Path -LiteralPath (Join-Path $R 'basic\scenes\OBS-Forge.json')) 'collection written'
    Assert (-not (Test-Path -LiteralPath (Join-Path $R 'basic\scenes\OBS-Forge Vertical.json'))) 'vertical collection only with the vertical preset'

    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 0 $V.Code "verify exit`n$($V.Out)"
    Assert ($V.Out -match 'Verify: PASS') 'verify says PASS'

    $Again = Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'nvenc', '-IgnoreRunning')
    AssertEq 0 $Again.Code 're-run exit'
    Assert ($Again.Out -match 'skipped:\s+OBS-Forge 1080p60') "re-run skips an up-to-date profile`n$($Again.Out)"

    $Forced = Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'nvenc', '-Force', '-IgnoreRunning')
    Assert ($Forced.Out -match 'reapplied:\s+OBS-Forge 1080p60') "-Force re-applies`n$($Forced.Out)"

    $Amd = Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'amf', '-Preset', '1080p60', '-IgnoreRunning')
    Assert ($Amd.Out -match 'reapplied:\s+OBS-Forge 1080p60 \(encoder nvenc -> amf\)') "encoder switch re-applies`n$($Amd.Out)"
    AssertEq 'h264_texture_amf' (Read-Ini (Join-Path $R 'basic\profiles\OBS-Forge 1080p60\basic.ini'))['AdvOut']['Encoder'] 'AMF stream encoder written'
}

Test-Case 'all presets install with x264 and verify' {
    $R = New-Root 'all-x264'
    $I = Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'x264', '-Preset', 'all', '-IgnoreRunning')
    AssertEq 0 $I.Code "install all exit`n$($I.Out)"
    AssertEq (@(Get-ForgePreset).Count) (@(Get-ForgeInstalledProfile $R).Count) 'every preset installed'
    Assert (Test-Path -LiteralPath (Join-Path $R 'basic\scenes\OBS-Forge Vertical.json')) 'vertical collection written'
    $D = Join-Path $R 'basic\profiles\OBS-Forge 1080p60'
    Assert (-not (Test-Path -LiteralPath (Join-Path $D 'recordEncoder.json'))) 'x264 light: no recordEncoder.json'
    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 0 $V.Code "verify all exit`n$($V.Out)"
    $L = Invoke-Script 'Install.ps1' @('-List', '-NoProbe')
    AssertEq 0 $L.Code 'list exit'
    Assert ($L.Out -match 'youtube-1440p60') 'list shows presets'
}

Test-Case 'verify catches drift without crashing' {
    $R = New-Root 'drift'
    [void](Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'nvenc', '-IgnoreRunning'))
    $D = Join-Path $R 'basic\profiles\OBS-Forge 1080p60'

    # What OBS 33 writes after the user presses OK in Settings: new keys, no preset2.
    Set-Content -LiteralPath (Join-Path $D 'recordEncoder.json') -Value '{ "rate_control": "CQP", "cqp": 20, "profile": "main", "preset": "p4" }'
    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 0 $V.Code "OBS-rewritten JSON passes`n$($V.Out)"
    Assert ($V.Out -notmatch 'null-valued') 'no crash on a JSON without preset2'

    # A 0.1.0-style legacy key is reported as a FAIL, not an exception.
    Set-Content -LiteralPath (Join-Path $D 'recordEncoder.json') -Value '{ "rate_control": "CQP", "cqp": 22, "profile": "main", "preset2": "p4" }'
    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 1 $V.Code 'legacy key fails'
    Assert ($V.Out -match "FAIL .*preset2.*OBS 31\+ ignores") "legacy key message`n$($V.Out)"

    Remove-Item -LiteralPath (Join-Path $D 'recordEncoder.json')
    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 1 $V.Code 'missing record JSON fails'
    Assert ($V.Out -match 'FAIL .*recordEncoder.json missing') 'missing record JSON message'

    [void](Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'nvenc', '-Force', '-IgnoreRunning'))
    $Ini = Join-Path $D 'basic.ini'
    $T = [System.IO.File]::ReadAllText($Ini) -replace 'ColorSpace=709', 'ColorSpace=2100PQ' -replace 'ColorFormat=NV12', 'ColorFormat=P010'
    [System.IO.File]::WriteAllText($Ini, $T)
    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 1 $V.Code 'HDR canvas fails'
    Assert ($V.Out -match 'FAIL OBS-Forge 1080p60 is 2100PQ/P010') 'HDR canvas message'

    # Log: the LAST video reset is reported.
    [void](Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'nvenc', '-Force', '-IgnoreRunning'))
    New-Item -ItemType Directory -Force -Path (Join-Path $R 'logs') | Out-Null
    $Log = @(
        '10:00:00.000: video settings reset:', '10:00:00.000: 	format:                   I444', '10:00:00.000: 	YUV mode:                 sRGB/Full',
        '10:00:05.000: video settings reset:', '10:00:05.000: 	format:                   NV12', '10:00:05.000: 	YUV mode:                 Rec. 709/Partial'
    ) -join "`r`n"
    Set-Content -LiteralPath (Join-Path $R 'logs\2026-01-01 10-00-00.txt') -Value $Log
    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 0 $V.Code "clean log passes`n$($V.Out)"
    Assert ($V.Out -match 'last canvas NV12 / Rec\. 709/Partial') "reports the last reset`n$($V.Out)"
    Add-Content -LiteralPath (Join-Path $R 'logs\2026-01-01 10-00-00.txt') -Value '10:00:09.000: [obs-nvenc] NVENC Error: Cannot perform 10-bit encode on this encoder'
    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 1 $V.Code 'NVENC 10-bit error fails'
}

Test-Case 'upgrade from 0.1.0 keeps account, hotkeys, user settings and scenes' {
    $R = New-Root 'upgrade'
    Copy-Item -LiteralPath (Join-Path $Fixtures 'profiles') -Destination (Join-Path $R 'basic\profiles') -Recurse
    New-Item -ItemType Directory -Force -Path (Join-Path $R 'basic\scenes') | Out-Null
    Copy-Item -LiteralPath (Join-Path $Fixtures 'scenes\OBS-Forge.json') -Destination (Join-Path $R 'basic\scenes\OBS-Forge.json')
    $D = Join-Path $R 'basic\profiles\OBS-Forge 1080p60'
    Set-Content -LiteralPath (Join-Path $D 'service.json') -Value '{"type":"rtmp_common","settings":{"service":"Twitch","key":"live_test_key"}}'
    $Ini = Join-Path $D 'basic.ini'
    $T = [System.IO.File]::ReadAllText($Ini) -replace 'MonitoringDeviceId=default', 'MonitoringDeviceId={my-headset}'
    $T += "`r`n[Hotkeys]`r`nOBSBasic.StartStreaming={`"bindings`":[{`"key`":`"OBS_KEY_F9`"}]}`r`n"
    [System.IO.File]::WriteAllText($Ini, $T, (New-Object System.Text.UTF8Encoding($true)))

    $Pre = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 1 $Pre.Code "0.1.0 install fails verify on the ignored NVENC keys`n$($Pre.Out)"

    $I = Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'nvenc', '-IgnoreRunning')
    AssertEq 0 $I.Code "upgrade exit`n$($I.Out)"
    Assert ($I.Out -match 'upgraded:\s+OBS-Forge 1080p60 \(from 0\.1\.0\)') "upgrade reported`n$($I.Out)"
    Assert ($I.Out -match 'updated:\s+scene collection OBS-Forge \(added Desktop Audio \+ Mic/Aux\)') 'collection audio added'
    Assert ((Get-Content -LiteralPath (Join-Path $D 'service.json') -Raw) -match 'live_test_key') 'service.json kept'
    $After = Read-Ini $Ini
    AssertEq '{my-headset}' $After['Audio']['MonitoringDeviceId'] 'user audio setting kept'
    Assert ($After.Contains('Hotkeys') -and $After['Hotkeys']['OBSBasic.StartStreaming'] -match 'OBS_KEY_F9') 'hotkeys kept'
    $S = Read-Json (Join-Path $D 'streamEncoder.json')
    AssertEq 'p5' $S.preset 'stream preset key fixed'
    Assert ($null -eq $S.PSObject.Properties['preset2']) 'legacy key gone'
    AssertEq 'p4' (Read-Json (Join-Path $D 'recordEncoder.json')).preset 'record preset now really P4'
    $C = Read-Json (Join-Path $R 'basic\scenes\OBS-Forge.json')
    AssertEq 'wasapi_output_capture' $C.DesktopAudioDevice1.id 'desktop audio added to the old collection'
    AssertEq 7 (@($C.sources | Where-Object { $_.id -ne 'scene' })).Count 'old scenes untouched (no game capture injected)'
    $Backups = @(Get-ChildItem -LiteralPath $env:OBSFORGE_BACKUP_ROOT -Recurse -Filter 'service.json')
    Assert ($Backups.Count -ge 1) 'backup taken before upgrade'

    $V = Invoke-Script 'Verify.ps1' @('-ConfigRoot', $R, '-NoProbe')
    AssertEq 0 $V.Code "verify after upgrade`n$($V.Out)"
}

Test-Case 'foreign profile with a pack name is not overwritten' {
    $R = New-Root 'foreign'
    $D = Join-Path $R 'basic\profiles\OBS-Forge 720p60'
    New-Item -ItemType Directory -Force -Path $D | Out-Null
    Set-Content -LiteralPath (Join-Path $D 'basic.ini') -Value "[General]`r`nName=OBS-Forge 720p60`r`n"
    $I = Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'nvenc', '-Preset', '720p60', '-IgnoreRunning')
    Assert ($I.Out -match 'skipped:\s+OBS-Forge 720p60 \(a profile with this name exists') "foreign skipped`n$($I.Out)"
    Assert (-not (Test-Path -LiteralPath (Join-Path $D 'streamEncoder.json'))) 'foreign folder untouched'
}

Test-Case 'uninstall removes only pack files' {
    $R = New-Root 'uninstall'
    [void](Invoke-Script 'Install.ps1' @('-ConfigRoot', $R, '-NoProbe', '-Encoder', 'qsv', '-Preset', '1080p60,vertical', '-IgnoreRunning'))
    $Mine = Join-Path $R 'basic\profiles\My Profile'
    New-Item -ItemType Directory -Force -Path $Mine | Out-Null
    Set-Content -LiteralPath (Join-Path $Mine 'basic.ini') -Value "[General]`r`nName=My Profile`r`n"
    Set-Content -LiteralPath (Join-Path $R 'basic\scenes\Mine.json') -Value '{"name":"Mine"}'
    $U = Invoke-Script 'Uninstall.ps1' @('-ConfigRoot', $R, '-Force', '-IgnoreRunning')
    AssertEq 0 $U.Code "uninstall exit`n$($U.Out)"
    AssertEq 0 (@(Get-ForgeInstalledProfile $R).Count) 'pack profiles gone'
    Assert (-not (Test-Path -LiteralPath (Join-Path $R 'basic\scenes\OBS-Forge.json'))) 'pack collection gone'
    Assert (-not (Test-Path -LiteralPath (Join-Path $R 'basic\scenes\OBS-Forge Vertical.json'))) 'vertical collection gone'
    Assert (Test-Path -LiteralPath $Mine) 'user profile kept'
    Assert (Test-Path -LiteralPath (Join-Path $R 'basic\scenes\Mine.json')) 'user collection kept'
    $Again = Invoke-Script 'Uninstall.ps1' @('-ConfigRoot', $R, '-Force', '-IgnoreRunning')
    AssertEq 0 $Again.Code 'second uninstall exit'
    Assert ($Again.Out -match 'Nothing to remove') 'second uninstall is a no-op'
}

# ---------------------------------------------------------------------------------------
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
$Edition = "$($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
Write-Host ''
if ($script:Failures.Count -eq 0) {
    Write-Host "Tests: PASS ($script:Pass assertions, PowerShell $Edition)"
    exit 0
}
$script:Failures | ForEach-Object { Write-Host "FAIL $_" }
Write-Host "Tests: $($script:Failures.Count) failed, $script:Pass passed (PowerShell $Edition)"
exit 1
