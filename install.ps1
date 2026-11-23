#Requires -Version 5.1
<#
.SYNOPSIS
  Windows entry point: checks the prerequisites, then runs install.sh in Git Bash.

.DESCRIPTION
  The brain's hooks are bash scripts; on Windows they run in Git Bash. This script
  finds Git Bash and a real Python 3, warns if the claude CLI is missing, and hands
  over to install.sh (init + hooks). It does not log in to GitHub and does not clone:
  you already made your brain repo from the template and cloned it.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -Name Atlas -Org "Acme"
  powershell -ExecutionPolicy Bypass -File install.ps1 -CheckOnly
#>
param(
  [switch]$CheckOnly,
  [string]$Name,
  [string]$Org
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$missing = 0

function Find-GitBash {
  # Prefer the bash that ships with git: <git>/bin/bash.exe next to --exec-path.
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    try {
      $exec = (& git --exec-path) 2>$null
      $base = Split-Path (Split-Path (Split-Path $exec))
      foreach ($c in @((Join-Path $base 'bin\bash.exe'), (Join-Path $base 'bin/bash'))) {
        if (Test-Path $c) { return $c }
      }
    } catch { }
  }
  # Otherwise any bash on PATH - but never WSL's System32\bash.exe (a Linux VM, not Git Bash).
  foreach ($b in @(Get-Command bash -All -ErrorAction SilentlyContinue)) {
    if ($b.Source -notmatch '\\System32\\') { return $b.Source }
  }
  return $null
}

function Find-Python {
  # Trust the OUTPUT, not the name: the Microsoft Store stub prints no "Python 3".
  $names = if ($env:KIT_PYTHON_NAMES) { $env:KIT_PYTHON_NAMES -split ',' } else { @('python3', 'python', 'py') }
  foreach ($n in $names) {
    $cmd = Get-Command $n -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    try { $v = (& $cmd.Source --version 2>&1 | Out-String) } catch { continue }
    if ($v -match 'Python 3') { return "$($cmd.Source) ($($v.Trim()))" }
  }
  return $null
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Write-Host "OK   git" } else {
  Write-Host "FAIL git - install Git for Windows: winget install --id Git.Git -e"; $missing++
}
$bash = Find-GitBash
if ($bash) { Write-Host "OK   Git Bash - $bash" } else {
  Write-Host "FAIL Git Bash - install Git for Windows (it brings Git Bash): winget install --id Git.Git -e"; $missing++
}
$py = Find-Python
if ($py) { Write-Host "OK   Python 3 - $py" } else {
  Write-Host "FAIL Python 3 - install it (winget install --id Python.Python.3.12 -e); the Microsoft Store 'python' stub does not count"; $missing++
}
if (Get-Command claude -ErrorAction SilentlyContinue) { Write-Host "OK   claude" } else {
  Write-Host "WARN claude - the Claude Code CLI is not on PATH; the brain's hooks run inside Claude Code"
}

if ($missing -gt 0) { Write-Host "Fix the FAIL lines above, then run this again."; exit 1 }
if ($CheckOnly) { exit 0 }

$script = (Join-Path $root 'install.sh') -replace '\\', '/'
$argv = @($script)
if ($Name) { $argv += @('--name', $Name) }
if ($Org) { $argv += @('--org', $Org) }
& $bash @argv
exit $LASTEXITCODE
