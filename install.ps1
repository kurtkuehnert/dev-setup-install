$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Public Windows bootstrap script; all real logic lives in `dev.ps1`.

$Repo = "kurtkuehnert/dev-setup"
$Dir = Join-Path (Join-Path (Join-Path $HOME "kurtkuehnert") "projects") "dev-setup"
$Vault = if ($env:PROTON_PASS_VAULT) { $env:PROTON_PASS_VAULT } else { "Dev Setup" }
$SessionDir = if ($env:PROTON_PASS_SESSION_DIR) { $env:PROTON_PASS_SESSION_DIR } else { Join-Path (Join-Path (Join-Path $HOME ".local") "state") "proton-pass\dev-id" }

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
Install-WingetPackage -Id "Proton.ProtonPass.CLI" -Name "Proton Pass CLI"

if (-not (Command-Exists gh)) { throw "GitHub CLI was installed, but gh was not found. Open a new PowerShell window and rerun this script." }
if (-not (Command-Exists git)) { throw "Git was installed, but git was not found. Open a new PowerShell window and rerun this script." }
if (-not (Command-Exists pass-cli)) { throw "Proton Pass CLI was installed, but pass-cli was not found. Open a new PowerShell window and rerun this script." }

if (-not (Test-Path -LiteralPath $SessionDir)) {
    New-Item -ItemType Directory -Path $SessionDir | Out-Null
}
$env:PROTON_PASS_SESSION_DIR = $SessionDir
$env:PROTON_PASS_VAULT = $Vault

if (-not (Test-NativeSuccess -Command "pass-cli" -CommandArgs @("info"))) {
    pass-cli logout *> $null
    if (Test-Path -LiteralPath $SessionDir) {
        Remove-Item -LiteralPath $SessionDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $SessionDir | Out-Null

    Info "Authenticating Proton Pass..."
    $securePat = Read-Host "Paste Proton Pass PAT (pst_...::...)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePat)
    try {
        $pat = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        if ([string]::IsNullOrWhiteSpace($pat)) {
            throw "No Proton Pass PAT entered."
        }
        pass-cli login --pat $pat *> $null
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $pat = $null
    }
}

function Get-PassField {
    param(
        [string]$Item,
        [string]$Field
    )

    $value = pass-cli item view --vault-name $Vault --item-title $Item --field $Field
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing Proton item field: $Item/$Field"
    }
    return $value
}

$githubToken = Get-PassField -Item "GitHub kurtkuehnert" -Field "token"
$env:GH_TOKEN = $githubToken
$env:GITHUB_TOKEN = $githubToken

$gitlabToken = Get-PassField -Item "GitLab nolag" -Field "token"
$env:GITLAB_TOKEN = $gitlabToken
$env:GITLAB_ACCESS_TOKEN = $gitlabToken

if (Test-Path -LiteralPath $Dir) {
    if ((Test-Path -LiteralPath (Join-Path $Dir ".git")) -or (Test-Path -LiteralPath (Join-Path $Dir ".jj"))) {
        Info "dev-setup already installed."
    } else {
        $children = @(Get-ChildItem -LiteralPath $Dir -Force)
        if ($children.Count -eq 0) {
            Remove-Item -LiteralPath $Dir -Force
        } else {
            throw "$Dir exists but is not a dev-setup checkout; refusing to overwrite it."
        }
    }
}

if (-not (Test-Path -LiteralPath $Dir)) {
    $parent = Split-Path -Parent $Dir
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    Info "Cloning dev-setup..."
    gh repo clone $Repo $Dir
} else {
    Info "Running dev pull..."
}

Install-DevLauncher
& (Join-Path $Dir "dev.ps1") pull
