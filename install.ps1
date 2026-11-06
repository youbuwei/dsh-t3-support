[CmdletBinding()]
param(
    [Alias("Profile")]
    [string]$ProfileName = "acp",
    [string[]]$Provider = @(),
    [switch]$Force,
    [switch]$ListProviders
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BeginMarker = "# >>> dsh-t3-support managed block >>>"
$EndMarker = "# <<< dsh-t3-support managed block <<<"
$ScriptDir = $PSScriptRoot
$RegistryPath = Join-Path $ScriptDir "providers.yml"

function Usage {
    Write-Host @"
Usage: .\install.ps1 [-Profile NAME] [-Provider ID...] [-Force]

Enables model provider routes for a dsh profile.
Pass multiple providers as a comma-separated list, for example:
  .\install.ps1 -Provider glm-cn,openrouter

Options:
  -Profile NAME       dsh profile to patch (default: acp)
  -Provider ID        enable providers from providers.yml
  -ListProviders      list provider registry IDs
  -Force              allow installing beside a manual llm-pi-ai patch
"@
}

function Get-RegistryEntries {
    $entries = [ordered]@{}
    $current = $null
    foreach ($line in [System.IO.File]::ReadAllLines($RegistryPath)) {
        if ($line -match "^[A-Za-z0-9_.-]+:\s*$") {
            $current = $Matches[1]
            $entries[$current] = @{}
            continue
        }
        if ($null -ne $current -and $line -match "^\s+([A-Za-z0-9_]+):\s*(.*?)\s*$") {
            $entries[$current][$Matches[1]] = $Matches[2]
        }
    }
    return $entries
}

function Write-TextFileNoBom {
    param([string]$Path, [string[]]$Lines)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }
    $temporary = Join-Path $directory ([System.IO.Path]::GetRandomFileName())
    $encoding = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllLines($temporary, $Lines, $encoding)
        Move-Item -Path $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path $temporary) {
            Remove-Item $temporary -Force
        }
    }
}

if (-not (Test-Path $RegistryPath)) {
    Write-Error "registry not found: $RegistryPath"
    exit 1
}

$registry = Get-RegistryEntries
if ($ListProviders) {
    $registry.Keys
    exit 0
}

if ($Provider.Count -eq 0) {
    Usage
    exit 2
}

foreach ($id in $Provider) {
    if (-not $registry.Contains($id) -or $registry[$id].Count -eq 0) {
        Write-Host "error: unknown provider '$id' in providers.yml" -ForegroundColor Red
        Write-Host "hint: .\install.ps1 -ListProviders"
        exit 2
    }
}

$profileDir = Join-Path (Join-Path (Join-Path $HOME ".dsh") "profiles") $ProfileName"
$patchFile = Join-Path $profileDir "cordis.patch.yml"
if (-not (Test-Path $profileDir)) {
    Write-Host "error: profile '$ProfileName' not found at $profileDir" -ForegroundColor Red
    Write-Host "hint: boot it once first, for example: dsh --profile $ProfileName --help"
    exit 1
}

if (-not (Test-Path $patchFile)) {
    Write-TextFileNoBom -Path $patchFile -Lines @("[]")
}

$patchLines = [System.IO.File]::ReadAllLines($patchFile)
$base = New-Object "System.Collections.Generic.List[string]"
$insideManagedBlock = $false
$currentRoutes = New-Object "System.Collections.Generic.List[string]"

foreach ($line in $patchLines) {
    if ($line -eq $BeginMarker) {
        $insideManagedBlock = $true
        continue
    }
    if ($line -eq $EndMarker) {
        $insideManagedBlock = $false
        continue
    }
    if ($insideManagedBlock) {
        if ($line -match "^\s{6}([A-Za-z0-9_.-]+):\s*$") {
            $currentRoutes.Add($Matches[1])
        }
        continue
    }
    if ($line -ne "[]") {
        $base.Add($line)
    }
}

$hasUnmanagedPatch = $false
foreach ($line in $base) {
    if ($line -match "^\s*(?:-\s+)?id:\s*llm-pi-ai\s*$") {
        $hasUnmanagedPatch = $true
        break
    }
}
if ($hasUnmanagedPatch -and -not $Force) {
    Write-Host "error: $patchFile already has an llm-pi-ai patch outside this plugin's block" -ForegroundColor Red
    Write-Host "hint: remove it, or rerun with -Force"
    exit 1
}

$enabled = New-Object "System.Collections.Generic.List[string]"
foreach ($id in $registry.Keys) {
    $route = [string]$registry[$id]["route"]
    $wasEnabled = $currentRoutes.Contains($route)
    $wasRequested = $Provider -contains $id
    if ($wasEnabled -or $wasRequested) {
        $enabled.Add($id)
    }
}

if ($enabled.Count -gt 0) {
    $output = New-Object "System.Collections.Generic.List[string]"
    foreach ($line in $base) {
        $output.Add($line)
    }
    if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne "") {
        $output.Add("")
    }
    $output.Add($BeginMarker)
    $output.Add("# Model provider routes managed by dsh-t3-support. Do not edit.")
    $output.Add("- id: llm-pi-ai")
    $output.Add("  config:")
    $output.Add("    providers:")
    foreach ($id in $enabled) {
        $output.Add("      " + $registry[$id]["route"] + ":")
        $output.Add("        apiKeyEnv: " + $registry[$id]["apiKeyEnv"])
        $output.Add("        displayName: " + $registry[$id]["displayName"])
    }
    $output.Add($EndMarker)
    Write-TextFileNoBom -Path $patchFile -Lines $output.ToArray()
    Write-Host "providers: $($enabled -join ' ') -> $patchFile"
}
else {
    if (@($base | Where-Object { $_ -match "^\s*-" }).Count -eq 0) {
        $base.Add("[]")
    }
    Write-TextFileNoBom -Path $patchFile -Lines $base.ToArray()
    Write-Host "providers: none enabled"
}

$dsh = Get-Command dsh -ErrorAction SilentlyContinue
if ($null -ne $dsh) {
    $ok = $true
    foreach ($id in $enabled) {
        $route = [string]$registry[$id]["route"]
        $dump = & dsh --profile $ProfileName --dump-config 2>$null
        if ($LASTEXITCODE -eq 0 -and (($dump -join "`n") -match [regex]::Escape($route))) {
            Write-Host "validate : $route OK"
        }
        else {
            Write-Host "validate : $route MISSING" -ForegroundColor Red
            $ok = $false
        }
    }
    if (-not $ok) {
        exit 1
    }
}
