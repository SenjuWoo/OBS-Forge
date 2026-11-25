#requires -Version 5.1
<#
Builds dist\OBS-Forge-<version>.zip from a committed revision (default HEAD) with
`git archive`, so the zip holds exactly what that commit holds - never stray local files.
Only runtime files go in: scripts, launchers, lib, presets, docs, README, LICENSE.

    .\tools\Build-Release.ps1
    .\tools\Build-Release.ps1 -Ref v0.2.0 -OutDir dist
#>
[CmdletBinding()]
param(
    [string]$Ref = 'HEAD',
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $Root 'lib\OBSForge.psm1') -Force
$Version = Get-ForgeVersion

# Runtime files only (build hygiene: no tests, plans, state, changelog or CI in the zip).
$Include = @(
    'Install.cmd', 'Install.ps1', 'Verify.cmd', 'Verify.ps1', 'Uninstall.cmd', 'Uninstall.ps1',
    'lib', 'presets', 'docs', 'README.md', 'LICENSE'
)
$MustHave = @('Install.cmd', 'Install.ps1', 'Verify.ps1', 'Uninstall.ps1', 'lib/OBSForge.psm1', 'presets/presets.psd1', 'README.md', 'LICENSE')
$MustNot = '^(tests|tools|\.github)/|^(PLAN|STATE|WORKSPACE_OWNERSHIP|CHANGELOG)\.md$|^backups/'

$Sha = (git -C $Root rev-parse $Ref).Trim()
if ($LASTEXITCODE -ne 0) { throw "git rev-parse $Ref failed" }
$CommitVersion = (git -C $Root show "${Sha}:lib/OBSForge.psm1" | Select-String "PackVersion = '([^']+)'").Matches[0].Groups[1].Value
if ($CommitVersion -ne $Version) { Write-Warning "Commit $Sha has version $CommitVersion; working tree has $Version. Naming the zip after the commit." ; $Version = $CommitVersion }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Zip = Join-Path (Resolve-Path -LiteralPath $OutDir).Path "OBS-Forge-$Version.zip"
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
git -C $Root archive --format=zip --prefix="OBS-Forge-$Version/" -o $Zip $Sha -- @Include
if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$Archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
try {
    $Names = @($Archive.Entries | ForEach-Object { $_.FullName.Substring("OBS-Forge-$Version/".Length) } | Where-Object { $_ -and -not $_.EndsWith('/') })
    $Missing = @($MustHave | Where-Object { $Names -notcontains $_ })
    $Extra = @($Names | Where-Object { $_ -match $MustNot })
    if ($Missing.Count) { throw "zip is missing: $($Missing -join ', ')" }
    if ($Extra.Count) { throw "zip contains non-runtime files: $($Extra -join ', ')" }
    # Batch files with LF line endings misparse labels and some commands.
    $Cmd = $Archive.Entries | Where-Object { $_.FullName.EndsWith('Install.cmd') } | Select-Object -First 1
    $Reader = New-Object System.IO.StreamReader($Cmd.Open())
    $CmdText = $Reader.ReadToEnd(); $Reader.Dispose()
    if ($CmdText -notmatch "`r`n") { throw 'Install.cmd in the zip has LF line endings' }
}
finally { $Archive.Dispose() }

$Hash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "commit:  $Sha"
Write-Host "zip:     $Zip"
Write-Host "files:   $($Names.Count)"
Write-Host "sha256:  $Hash"
