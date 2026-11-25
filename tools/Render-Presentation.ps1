#requires -Version 5.1
<#
Renders the README / social images that are not OBS screenshots:
  docs\presentation\logo.png            512x512 from src\logo.svg
  docs\presentation\social-preview.png  1280x640 from src\social.html (GitHub social card)
  docs\presentation\hero.png            1920x1080, obs-main.png framed (src\hero.html)
  docs\presentation\installer.png       real Install.ps1 -Menu output, drawn as a terminal
  docs\presentation\verify.png          real Verify.ps1 output, drawn as a terminal
The console text comes from running the real scripts against a throw-away config root;
only that temp path is shown as %APPDATA%\obs-studio. Uses Microsoft Edge headless.
OBS screenshots: tools\Capture-Screenshots.ps1.

    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Render-Presentation.ps1
#>
[CmdletBinding()]
param([string]$Edge)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $Root 'docs\presentation'
$Src = Join-Path $Out 'src'
if (-not $Edge) {
    $Edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Edge) { throw 'Microsoft Edge not found; pass -Edge <path to msedge.exe or chrome.exe>' }

function Invoke-Shot([string]$Url, [int]$W, [int]$H, [string]$Png, [double]$Scale = 1, [switch]$Transparent) {
    $Args_ = @('--headless=new', '--disable-gpu', '--hide-scrollbars', "--force-device-scale-factor=$Scale",
        "--window-size=$W,$H", "--screenshot=`"$Png`"")
    if ($Transparent) { $Args_ += '--default-background-color=00000000' }
    $P = Start-Process -FilePath $Edge -ArgumentList ($Args_ + $Url) -PassThru -WindowStyle Hidden
    if (-not $P.WaitForExit(60000)) { try { $P.Kill() } catch { }; throw "Edge timed out on $Url" }
    if (-not (Test-Path -LiteralPath $Png)) { throw "Edge wrote no image for $Url" }
    Write-Host "rendered $Png"
}
function To-Url([string]$Path) { 'file:///' + ($Path -replace '\\', '/').Replace(' ', '%20') }

Invoke-Shot (To-Url (Join-Path $Src 'logo.svg')) 256 256 (Join-Path $Out 'logo.png') 2 -Transparent
Invoke-Shot (To-Url (Join-Path $Src 'social.html')) 1280 640 (Join-Path $Out 'social-preview.png')
# 16:9 hero = the real OBS screenshot from Capture-Screenshots.ps1, framed; no text overlay.
if (Test-Path -LiteralPath (Join-Path $Out 'obs-main.png')) { Invoke-Shot (To-Url (Join-Path $Src 'hero.html')) 1920 1080 (Join-Path $Out 'hero.png') }

# --- real console output -------------------------------------------------------------------
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("obsforge-render-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$Cfg = Join-Path $Tmp 'cfg'
$env:OBSFORGE_BACKUP_ROOT = Join-Path $Tmp 'backups'
$Ps = (Get-Process -Id $PID).Path
try {
    $Menu = "1, 3, 5`r`n`r`nn`r`n" | & $Ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'Install.ps1') -Menu -ConfigRoot $Cfg -IgnoreRunning 2>&1 | Out-String
    $Verify = & $Ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'Verify.ps1') -ConfigRoot $Cfg 2>&1 | Out-String
}
finally { Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue }

function Clean([string]$T) { ($T.Replace($Cfg, '%APPDATA%\obs-studio') -replace "`r", '').TrimEnd() -split "`n" }

# Piped answers show up as bare lines; put the prompt Read-Host would have shown back in front.
$MenuLines = New-Object System.Collections.ArrayList
$Answers = 0
foreach ($L in (Clean $Menu)) {
    if ($Answers -eq 0 -and $L -eq '1, 3, 5') { [void]$MenuLines.Add('>>Numbers separated by commas, A for all, Enter for the recommended pair: |1, 3, 5'); $Answers++; continue }
    if ($Answers -eq 1 -and $L -eq '') { [void]$MenuLines.Add('>>Encoder [Enter = nvenc, or nvenc / amf / qsv / x264]: |'); $Answers++; continue }
    if ($L -eq 'n') { continue }
    [void]$MenuLines.Add($L)
}
# Keep the picture short: stop after the read-back block.
$Cut = $MenuLines.IndexOf('Next:')
if ($Cut -gt 0) { $MenuLines = $MenuLines.GetRange(0, $Cut - 1) }
$VerifyLines = Clean $Verify

function Format-Line([string]$L) {
    if ($L.StartsWith('>>')) {
        $Parts = $L.Substring(2) -split '\|', 2
        return '<span class="dim">' + [System.Net.WebUtility]::HtmlEncode($Parts[0]) + '</span><span class="in">' + [System.Net.WebUtility]::HtmlEncode($Parts[1]) + '</span>'
    }
    $E = [System.Net.WebUtility]::HtmlEncode($L)
    $E = $E -replace '^(ok)(\s)', '<span class="ok">$1</span>$2'
    $E = $E -replace '^(warn)(\s)', '<span class="warn">$1</span>$2'
    $E = $E -replace '^(FAIL)(\s)', '<span class="fail">$1</span>$2'
    $E = $E -replace '^(note .*)$', '<span class="dim">$1</span>'
    $E = $E -replace '^(Verify: PASS.*)$', '<span class="pass">$1</span>'
    $E = $E -replace '^(  (Stream|YouTube|Record|Vertical))$', '<span class="head">$1</span>'
    $E = $E -replace '^(\s+)(\d\))', '$1<span class="num">$2</span>'
    $E = $E -replace '\[recommended\]', '<span class="rec">[recommended]</span>'
    $E = $E -replace '^(installed:|scenes:|upgraded:)', '<span class="ok">$1</span>'
    $E = $E -replace '^(OBS-Forge 0\.2\.0.*|Pick what you want OBS set up for:|Read back:)$', '<span class="title">$1</span>'
    return $E
}

$Template = [System.IO.File]::ReadAllText((Join-Path $Src 'terminal.html'))
foreach ($Shot in @(@('Install.cmd', $MenuLines, 'installer.png'), @('Verify.cmd', $VerifyLines, 'verify.png'))) {
    $Body = ($Shot[1] | ForEach-Object { Format-Line $_ }) -join "`n"
    $Html = $Template.Replace('{{TITLE}}', $Shot[0]).Replace('{{BODY}}', $Body)
    $Page = Join-Path $Src "_$($Shot[2]).html"
    [System.IO.File]::WriteAllText($Page, $Html, (New-Object System.Text.UTF8Encoding($false)))
    $H = 96 + 22 * @($Shot[1]).Count
    Invoke-Shot (To-Url $Page) 1180 $H (Join-Path $Out $Shot[2]) 1.5
    Remove-Item -LiteralPath $Page -Force
}
