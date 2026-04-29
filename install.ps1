$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Public Windows bootstrap script; all real logic lives in `dev.ps1`.

$Repo = "kurtkuehnert/dev-setup"
$Dir = Join-Path $HOME "dev-setup"

function Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Command-Exists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-NativeSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$CommandArgs = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        $script:ErrorActionPreference = "Continue"
        & $Command @CommandArgs *> $null
        return $LASTEXITCODE -eq 0
    } finally {
        $script:ErrorActionPreference = $previousPreference
    }
}

function Add-ProcessPath {
    param([string]$Path)
    if ((Test-Path -LiteralPath $Path) -and (($env:Path -split ";") -notcontains $Path)) {
        $env:Path = "$Path;$env:Path"
    }
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($pathValue in @($machinePath, $userPath)) {
        if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
            foreach ($part in ($pathValue -split ";" | Where-Object { $_ })) {
                Add-ProcessPath $part
            }
        }
    }

    Add-ProcessPath "C:\Program Files\GitHub CLI"
    Add-ProcessPath "C:\Program Files\Git\cmd"
    Add-ProcessPath "$HOME\bin"
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name = $Id
    )

    $existing = winget list --id $Id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and ($existing -match [regex]::Escape($Id))) {
        return
    }

    Info "Installing $Name..."
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

function Install-DevLauncher {
    $binDir = Join-Path $HOME "bin"
    if (-not (Test-Path -LiteralPath $binDir)) {
        New-Item -ItemType Directory -Path $binDir | Out-Null
    }

    $cmdPath = Join-Path $binDir "dev.cmd"
    $cmdContent = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$Dir\dev.ps1" %*
"@
    Set-Content -LiteralPath $cmdPath -Value $cmdContent -Encoding ASCII

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $parts = $userPath -split ";" | Where-Object { $_ }
    }
    if ($parts -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable("Path", (@($binDir) + $parts) -join ";", "User")
    }

    Refresh-Path
}

if ($env:OS -ne "Windows_NT") {
    throw "This installer is intended for native Windows."
}

if (-not (Command-Exists winget)) {
    throw "winget is required. Install Microsoft App Installer from the Microsoft Store, then rerun this script."
}

Refresh-Path
Install-WingetPackage -Id "GitHub.cli" -Name "GitHub CLI"
Install-WingetPackage -Id "Git.Git" -Name "Git"

if (-not (Command-Exists gh)) { throw "GitHub CLI was installed, but gh was not found. Open a new PowerShell window and rerun this script." }
if (-not (Command-Exists git)) { throw "Git was installed, but git was not found. Open a new PowerShell window and rerun this script." }

if (-not (Test-NativeSuccess -Command "gh" -CommandArgs @("auth", "status", "--hostname", "github.com"))) {
    Info "Authenticating with GitHub..."
    gh auth login --hostname github.com -p https -w -s repo
}

if (Test-Path -LiteralPath $Dir) {
    Info "dev-setup already installed, running pull..."
    git -C $Dir pull --ff-only
} else {
    Info "Cloning dev-setup..."
    gh repo clone $Repo $Dir
}

Install-DevLauncher
& (Join-Path $Dir "dev.ps1") pull
