[CmdletBinding()]
param(
    [Alias("Profile")]
    [string]$ProfileName = "acp",
    [string[]]$Provider = @(),
    [switch]$All,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BeginMarker = "# >>> dsh-t3-support managed block >>>"
$EndMarker = "# <<< dsh-t3-support managed block <<<"
$ScriptDir = $PSScriptRoot
$RegistryPath = Join-Path $ScriptDir "providers.yml"

function Usage {
    Write-Host @"
Usage: .\uninstall.ps1 [-Profile NAME] [-Provider ID...] [-All]

Removes provider routes installed by dsh-t3-support.
Pass multiple providers as a comma-separated list, for example:
  .\uninstall.ps1 -Provider glm-cn,openrouter
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

if ($Help) {
    Usage
    exit 0
}

if (-not (Test-Path $RegistryPath)) {
    Write-Error "registry not found: $RegistryPath"
    exit 1
}

$registry = Get-RegistryEntries
if ($All) {
    $Provider = @($registry.Keys)
}

if ($Provider.Count -eq 0) {
    Usage
    exit 2
}

foreach ($id in $Provider) {
    if (-not $registry.Contains($id)) {
        Write-Host "error: unknown provider '$id' in providers.yml" -ForegroundColor Red
        exit 2
    }
}

$patchFile = Join-Path (Join-Path (Join-Path (Join-Path $HOME ".dsh") "profiles") $ProfileName) "cordis.patch.yml"
if (Test-Path $patchFile) {
    $patchLines = [System.IO.File]::ReadAllLines($patchFile)
    if (($patchLines -contains $BeginMarker) -and ($patchLines -contains $EndMarker)) {
        $base = New-Object "System.Collections.Generic.List[string]"
        $currentRoutes = New-Object "System.Collections.Generic.List[string]"
        $insideManagedBlock = $false

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
            $base.Add($line)
        }

        $keep = New-Object "System.Collections.Generic.List[string]"
        foreach ($id in $registry.Keys) {
            $route = [string]$registry[$id]["route"]
            $wasEnabled = $currentRoutes.Contains($route)
            $requestedRemoval = $Provider -contains $id
            if ($wasEnabled -and -not $requestedRemoval) {
                $keep.Add($id)
            }
        }

        if ($keep.Count -gt 0) {
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
            foreach ($id in $keep) {
                $output.Add("      " + $registry[$id]["route"] + ":")
                $output.Add("        apiKeyEnv: " + $registry[$id]["apiKeyEnv"])
                $output.Add("        displayName: " + $registry[$id]["displayName"])
            }
            $output.Add($EndMarker)
            Write-TextFileNoBom -Path $patchFile -Lines $output.ToArray()
            Write-Host "providers kept: $($keep -join ' ')"
        }
        else {
            if (@($base | Where-Object { $_ -match "^\s*-" }).Count -eq 0) {
                $base.Add("[]")
            }
            Write-TextFileNoBom -Path $patchFile -Lines $base.ToArray()
            Write-Host "providers: none enabled"
        }
    }
    else {
        Write-Host "providers: no managed block in $patchFile"
    }
}
