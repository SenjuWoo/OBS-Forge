#requires -Version 5.1
<#
Regenerates the README screenshots from the real OBS: installs presets into an isolated
portable OBS (junction copy in %TEMP%, never %APPDATA%), opens it on OBS-Forge 1080p60,
and captures the main window plus the Output and Advanced settings pages with PrintWindow
(works even when other windows overlap). Local only; needs OBS installed.

    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Capture-Screenshots.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [int]$Width = 1600,
    [int]$Height = 900
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
# Relative to the repo, not the caller's folder (PS 5.1 has no $PSScriptRoot in param defaults).
if (-not $OutDir) { $OutDir = Join-Path $Root 'docs\presentation' }
Import-Module (Join-Path $Root 'lib\OBSForge.psm1') -Force
Add-Type -AssemblyName System.Drawing, UIAutomationClient, UIAutomationTypes

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ForgeWin {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
[void][ForgeWin]::SetProcessDpiAwarenessContext([IntPtr](-4))   # per-monitor v2: real pixels

function Save-Window([IntPtr]$Hwnd, [string]$Path) {
    $R = New-Object ForgeWin+RECT
    [void][ForgeWin]::GetClientRect($Hwnd, [ref]$R)
    $Bmp = New-Object System.Drawing.Bitmap ($R.R - $R.L), ($R.B - $R.T)
    $G = [System.Drawing.Graphics]::FromImage($Bmp)
    $Dc = $G.GetHdc()
    # 1 = client area only (no title bar), 2 = PW_RENDERFULLCONTENT (DirectX/Qt content).
    [void][ForgeWin]::PrintWindow($Hwnd, $Dc, 3)
    $G.ReleaseHdc($Dc); $G.Dispose()
    $Bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png); $Bmp.Dispose()
    Write-Host "saved $Path"
}

function Find-Element($Parent, [string]$Name, $Type) {
    $C = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $Type)))
    return $Parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $C)
}

$Obs = Find-ForgeObs
if (-not $Obs) { throw 'OBS not installed' }
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("obsforge-shots-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$Portable = Join-Path $Work 'obs'
New-Item -ItemType Directory -Force -Path $Portable | Out-Null
foreach ($D in 'bin', 'data', 'core') { New-Item -ItemType Junction -Path (Join-Path $Portable $D) -Target (Join-Path $Obs $D) | Out-Null }
Set-Content -LiteralPath (Join-Path $Portable 'portable_mode.txt') -Value ''
$Config = Join-Path $Portable 'config\obs-studio'
New-Item -ItemType Directory -Force -Path $Config | Out-Null
Set-Content -LiteralPath (Join-Path $Config 'user.ini') -Value "[General]`r`nFirstRun=true`r`n"
$env:OBSFORGE_BACKUP_ROOT = Join-Path $Work 'backups'
& (Join-Path $Root 'Install.ps1') -ConfigRoot $Config -Preset recommended -IgnoreRunning | Out-Null

# Open on the Starting Soon scene so the preview shows something (Live is black without a game).
$Coll = Join-Path $Config 'basic\scenes\OBS-Forge.json'
$J = [System.IO.File]::ReadAllText($Coll) -replace '"current_scene":\s*"Live"', '"current_scene": "Starting Soon"' -replace '"current_program_scene":\s*"Live"', '"current_program_scene": "Starting Soon"'
[System.IO.File]::WriteAllText($Coll, $J)

$Bin = Join-Path $Portable 'bin\64bit'
$P = Start-Process -FilePath (Join-Path $Bin 'obs64.exe') -WorkingDirectory $Bin -PassThru -ArgumentList @(
    '--portable', '--multi', '--disable-updater', '--disable-shutdown-check',
    '--profile', '"OBS-Forge 1080p60"', '--collection', '"OBS-Forge"')
try {
    $Hwnd = [IntPtr]::Zero
    for ($i = 0; $i -lt 40 -and $Hwnd -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 500; $P.Refresh(); $Hwnd = $P.MainWindowHandle }
    if ($Hwnd -eq [IntPtr]::Zero) { throw 'OBS main window not found' }
    [void][ForgeWin]::ShowWindow($Hwnd, 9)
    [void][ForgeWin]::SetWindowPos($Hwnd, [IntPtr]::Zero, 40, 40, $Width, $Height, 0x0044)
    Start-Sleep -Seconds 4
    Save-Window $Hwnd (Join-Path $OutDir 'obs-main.png')

    $Main = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    $Btn = Find-Element $Main 'Settings' ([System.Windows.Automation.ControlType]::Button)
    if (-not $Btn) { throw 'Settings button not found via UI Automation' }
    $Btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Seconds 2
    $Desk = [System.Windows.Automation.AutomationElement]::RootElement
    $Cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $P.Id)
    $Settings = $Desk.FindAll([System.Windows.Automation.TreeScope]::Children, $Cond) | Where-Object { $_.Current.Name -eq 'Settings' } | Select-Object -First 1
    if (-not $Settings) { $Settings = $Main.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Settings'))) }
    $SHwnd = [IntPtr]$Settings.Current.NativeWindowHandle
    [void][ForgeWin]::SetWindowPos($SHwnd, [IntPtr]::Zero, 80, 60, 1280, 860, 0x0044)
    # Qt switches pages on a real click, not on a UIA Select. Post the click straight to the
    # Settings window at the list item's centre: no real mouse movement, no focus needed.
    foreach ($Page in @(@('Output', 'obs-settings-output.png'), @('Advanced', 'obs-settings-advanced.png'))) {
        $Item = Find-Element $Settings $Page[0] ([System.Windows.Automation.ControlType]::ListItem)
        if (-not $Item) { Write-Warning "settings page $($Page[0]) not found"; continue }
        $B = $Item.Current.BoundingRectangle
        $Pt = New-Object ForgeWin+POINT
        $Pt.X = [int]($B.X + $B.Width / 2); $Pt.Y = [int]($B.Y + $B.Height / 2)
        [void][ForgeWin]::ScreenToClient($SHwnd, [ref]$Pt)
        $L = [IntPtr](($Pt.Y -shl 16) -bor ($Pt.X -band 0xFFFF))
        [void][ForgeWin]::PostMessage($SHwnd, 0x0201, [IntPtr]1, $L)   # WM_LBUTTONDOWN
        [void][ForgeWin]::PostMessage($SHwnd, 0x0202, [IntPtr]0, $L)   # WM_LBUTTONUP
        Start-Sleep -Seconds 2
        Save-Window $SHwnd (Join-Path $OutDir $Page[1])
    }
}
finally {
    try { $P.Kill() } catch { }
    $P.WaitForExit(10000) | Out-Null
    foreach ($D in 'bin', 'data', 'core') { $Jn = Join-Path $Portable $D; if (Test-Path -LiteralPath $Jn) { [System.IO.Directory]::Delete($Jn) } }
    $Left = @(Get-ChildItem -LiteralPath $Portable -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    if ($Left.Count -eq 0) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }
}
