<#
    run.ps1 - Syntax-check the addon and the probe, and run every tests\test_*.lua under Lua 5.1,
    through WowTestKit at the commit tests\kit.pin names (its scripts\run.ps1).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev      # the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# The tests load the LibGlass checkout as it is; CI loads the .pkgmeta pin.
$libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
. (Join-Path $RepoRoot "Tools\LibGlassPin.ps1")
if (Test-Path -LiteralPath $libGlass) { Write-LibGlassPinStatus $RepoRoot $libGlass "CI tests the pin" }

# The probe's files are syntax-checked too (the kit checks the TOC's).
$probeToc = Join-Path $RepoRoot "Tools\GABProbe\GABProbe.toc"
$probeFiles = @()
if (Test-Path -LiteralPath $probeToc) {
    $probeFiles = @(Get-Content $probeToc | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" } | ForEach-Object { "Tools\GABProbe\$_" })
}

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassActionBars.toc" -Extra $probeFiles -Lua $Lua
exit $LASTEXITCODE
