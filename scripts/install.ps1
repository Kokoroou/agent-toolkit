# One-command setup of the agent pipeline in a project repository (Windows).
#
#   irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1))) --stack python --ref v0
#
# Installs Git for Windows and the GitHub CLI with winget when they are missing, then runs
# scripts/install.sh with Git Bash in the current directory. Arguments and environment
# variables are the same as install.sh (see `--help`).

# Wrapped in a script block so `irm | iex` leaves no variables or preferences behind.
& {
  $ErrorActionPreference = 'Stop'
  $raw = if ($env:AGENT_TOOLKIT_RAW) { $env:AGENT_TOOLKIT_RAW } else { 'https://raw.githubusercontent.com/kokoroou/agent-toolkit/main' }

  function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  }

  function Install-Tool([string]$Command, [string]$WingetId, [string]$Url) {
    if (Get-Command $Command -ErrorAction SilentlyContinue) { return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
      throw "$Command is not installed and winget is unavailable - install it from $Url and run again."
    }
    Write-Host "==> Installing $WingetId with winget"
    winget install --id $WingetId -e --source winget --accept-source-agreements --accept-package-agreements
    Update-Path
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
      throw "$Command was installed but is not on PATH yet - open a new terminal and run again."
    }
  }

  Install-Tool git 'Git.Git' 'https://git-scm.com/download/win'
  Install-Tool gh 'GitHub.cli' 'https://cli.github.com'

  # Git Bash (not WSL's bash.exe in System32): <Git>\cmd\git.exe → <Git>\bin\bash.exe
  $gitRoot = Split-Path (Split-Path (Get-Command git).Source -Parent) -Parent
  $bash = @("$gitRoot\bin\bash.exe", "$gitRoot\usr\bin\bash.exe", "$env:ProgramFiles\Git\bin\bash.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $bash) { throw "Git Bash not found next to $((Get-Command git).Source) - reinstall Git for Windows." }

  # Use install.sh next to this file (toolkit checkout) or download it (irm | iex).
  $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'install.sh' } else { $null }
  if ($local -and (Test-Path $local)) {
    $script = $local -replace '\\', '/'   # bash's dirname needs forward slashes
  } else {
    $script = Join-Path ([IO.Path]::GetTempPath()) "agent-toolkit-install-$PID.sh"
    $content = (Invoke-RestMethod "$raw/scripts/install.sh") -replace "`r`n", "`n"
    [IO.File]::WriteAllText($script, $content, (New-Object Text.UTF8Encoding $false))
  }

  try {
    & $bash $script @args
    if ($LASTEXITCODE -ne 0) { throw "install.sh failed (exit code $LASTEXITCODE)" }
  } finally {
    if (-not ($local -and (Test-Path $local))) { Remove-Item $script -ErrorAction SilentlyContinue }
  }
} @args
