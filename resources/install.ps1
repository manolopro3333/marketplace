[CmdletBinding()]
param(
    [Parameter()]
    [switch]$BypassAdmin
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$spicetifyCommand = Get-Command -Name 'spicetify' -ErrorAction 'SilentlyContinue'
if ($spicetifyCommand) {
    $spicetifyExecutable = $spicetifyCommand.Source
}
if (-not $spicetifyExecutable) {
    $candidatePaths = @(
        "$env:LOCALAPPDATA\spicetify\spicetify.exe",
        "$env:LOCALAPPDATA\spicetify\spicetify",
        "$HOME\.spicetify\spicetify.exe",
        "$HOME\.spicetify\spicetify"
    )

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -Path $candidatePath -PathType 'Leaf') {
            $spicetifyExecutable = (Resolve-Path -Path $candidatePath).Path
            break
        }
    }
}

if (-not $spicetifyExecutable) {
    Write-Host -Object 'Spicetify not found.' -ForegroundColor 'Yellow'
    Write-Host -Object 'Install the forked CLI first, then open a new terminal and rerun Marketplace.' -ForegroundColor 'Red'
    return
}

function Invoke-Spicetify {
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    
    $spicetifyArgs = @()
    if ($BypassAdmin) {
        $spicetifyArgs += "--bypass-admin"
    }
    $spicetifyArgs += $Arguments
    
    & $spicetifyExecutable @spicetifyArgs
    return $LASTEXITCODE
}

function Invoke-SpicetifyWithOutput {
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    
    $spicetifyArgs = @()
    if ($BypassAdmin) {
        $spicetifyArgs += "--bypass-admin"
    }
    $spicetifyArgs += $Arguments
    
    $output = ""
    $exitCode = 0
    
    try {
        $output = (& $spicetifyExecutable @spicetifyArgs 2>&1 | Out-String).Trim()
        $exitCode = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }
    
    return @{
        Output = $output
        ExitCode = $exitCode
    }
}

function Get-SpicetifyUserDataPath {
    if ($env:SPICETIFY_CONFIG) {
        return $env:SPICETIFY_CONFIG
    }

    return Join-Path -Path $env:APPDATA -ChildPath 'spicetify'
}

function Get-SpicetifyCurrentTheme {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -Path $ConfigPath -PathType 'Leaf')) {
        return ''
    }

    $inSettingSection = $false
    foreach ($line in Get-Content -Path $ConfigPath -ErrorAction 'SilentlyContinue') {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -match '^\[(.+)\]$') {
            $inSettingSection = $Matches[1] -eq 'Setting'
            continue
        }

        if (-not $inSettingSection) {
            continue
        }

        if ($trimmedLine -match '^current_theme\s*=\s*(.*)$') {
            return $Matches[1].Trim()
        }
    }

    return ''
}

Write-Host -Object 'Setting up...' -ForegroundColor 'Cyan'

Write-Host -Object 'Verifying Spicetify installation...' -ForegroundColor 'Gray'
if (-not (Get-Command -Name 'spicetify' -ErrorAction 'SilentlyContinue')) {
    Write-Host -Object 'Spicetify not found.' -ForegroundColor 'Yellow'
    Write-Host -Object 'Install the forked CLI first, then rerun Marketplace from a new terminal.' -ForegroundColor 'Red'
    return
}
Write-Host -Object 'Spicetify found!' -ForegroundColor 'Green'

Write-Host -Object 'Getting Spicetify paths...' -ForegroundColor 'Gray'
try {
    $spiceUserDataPath = Get-SpicetifyUserDataPath
    if ([string]::IsNullOrWhiteSpace($spiceUserDataPath)) {
        throw 'Unable to determine the Spicetify user data path.'
    }

    Write-Host -Object "User data path: $spiceUserDataPath" -ForegroundColor 'Gray'
} catch {
    Write-Host -Object "Error determining Spicetify path:" -ForegroundColor 'Red'
    Write-Host -Object $_.Exception.Message.Trim() -ForegroundColor 'Red'
    return
}

if (-not (Test-Path -Path $spiceUserDataPath -PathType 'Container' -ErrorAction 'SilentlyContinue')) {
    $spiceUserDataPath = "$env:APPDATA\spicetify"
}
$spicetifyConfigPath = Join-Path -Path $spiceUserDataPath -ChildPath 'config-xpui.ini'
$marketAppPath = "$spiceUserDataPath\CustomApps\marketplace"
$marketThemePath = "$spiceUserDataPath\Themes\marketplace"

Write-Host -Object 'Checking theme installation...' -ForegroundColor 'Gray'
$isThemeInstalled = Test-Path -Path (Join-Path -Path $spiceUserDataPath -ChildPath 'Themes') -PathType 'Container'
Write-Host -Object "Theme installed: $isThemeInstalled" -ForegroundColor 'Gray'

Write-Host -Object 'Getting current theme...' -ForegroundColor 'Gray'
$currentTheme = Get-SpicetifyCurrentTheme -ConfigPath $spicetifyConfigPath
Write-Host -Object "Current theme: $currentTheme" -ForegroundColor 'Gray'
$setTheme = $true

Write-Host -Object 'Removing and creating Marketplace folders...' -ForegroundColor 'Cyan'
try {
    Write-Host -Object "  Removing old marketplace files..." -ForegroundColor 'Gray'
    Remove-Item -Path $marketAppPath, $marketThemePath -Recurse -Force -ErrorAction 'SilentlyContinue' | Out-Null
    
    Write-Host -Object "  Creating new marketplace directories..." -ForegroundColor 'Gray'
    if (-not (New-Item -Path $marketAppPath, $marketThemePath -ItemType 'Directory' -Force -ErrorAction 'Stop')) {
        Write-Host -Object "Error: Failed to create Marketplace directories." -ForegroundColor 'Red'
        return
    }
    Write-Host -Object '  Directories ready' -ForegroundColor 'Green'
} catch {
    Write-Host -Object "Error: $($_.Exception.Message.Trim())" -ForegroundColor 'Red'
    return
}

Write-Host -Object 'Downloading Marketplace...' -ForegroundColor 'Cyan'
$marketArchivePath = "$marketAppPath\marketplace.zip"
$unpackedFolderPath = "$marketAppPath\marketplace-dist"
$Parameters = @{
    Uri             = 'https://github.com/manolopro3333/marketplace/releases/latest/download/marketplace.zip'
    UseBasicParsing = $true
    OutFile         = $marketArchivePath
}
Write-Host -Object '  Downloading from GitHub...' -ForegroundColor 'Gray'
try {
    Invoke-WebRequest @Parameters
    Write-Host -Object '  Download complete' -ForegroundColor 'Green'
} catch {
    Write-Host -Object "Error: Failed to download marketplace" -ForegroundColor 'Red'
    Write-Host -Object $_.Exception.Message -ForegroundColor 'Red'
    return
}

Write-Host -Object 'Unzipping and installing...' -ForegroundColor 'Cyan'
Write-Host -Object '  Extracting files...' -ForegroundColor 'Gray'
Expand-Archive -Path $marketArchivePath -DestinationPath $marketAppPath -Force
Write-Host -Object '  Moving files to marketplace directory...' -ForegroundColor 'Gray'
Move-Item -Path "$unpackedFolderPath\*" -Destination $marketAppPath -Force
Write-Host -Object '  Cleaning up temporary files...' -ForegroundColor 'Gray'
Remove-Item -Path $marketArchivePath, $unpackedFolderPath -Force

# Disable previous marketplace version
Write-Host -Object '  Disabling old marketplace version...' -ForegroundColor 'Gray'
$disableResult = Invoke-Spicetify "config" "custom_apps" "spicetify-marketplace-" "-q"
if ($LASTEXITCODE -ne 0) {
    Write-Host -Object "Warning: Could not disable old marketplace version" -ForegroundColor 'Yellow'
}

# Enable new marketplace
Write-Host -Object '  Enabling new marketplace...' -ForegroundColor 'Gray'
$enableResult = Invoke-Spicetify "config" "custom_apps" "marketplace"
if ($LASTEXITCODE -ne 0) {
    Write-Host -Object "Error: Could not enable marketplace" -ForegroundColor 'Red'
    Write-Host -Object "Details: $enableResult" -ForegroundColor 'Red'
    return
}

Write-Host -Object '  Configuring CSS injection...' -ForegroundColor 'Gray'
Invoke-Spicetify "config" "inject_css" "1" "replace_colors" "1"
Write-Host -Object '  Installation complete' -ForegroundColor 'Green'

Write-Host -Object 'Downloading placeholder theme...' -ForegroundColor 'Cyan'
$Parameters = @{
    Uri             = 'https://raw.githubusercontent.com/manolopro3333/marketplace/main/resources/color.ini'
    UseBasicParsing = $true
    OutFile         = "$marketThemePath\color.ini"
}
Write-Host -Object '  Downloading from GitHub...' -ForegroundColor 'Gray'
try {
    Invoke-WebRequest @Parameters
    Write-Host -Object '  Download complete' -ForegroundColor 'Green'
} catch {
    Write-Host -Object "Error: Failed to download theme" -ForegroundColor 'Red'
    Write-Host -Object $_.Exception.Message -ForegroundColor 'Red'
}

Write-Host -Object 'Applying configuration...' -ForegroundColor 'Cyan'
if ($isThemeInstalled -and ($currentTheme -ne 'marketplace')) {
    $Host.UI.RawUI.Flushinputbuffer()
    $choice = $Host.UI.PromptForChoice(
        'Local theme found',
        'Do you want to replace it with a placeholder to install themes from the Marketplace?',
        ('&Yes', '&No'),
        0
    )
    if ($choice -eq 1) { $setTheme = $false }
}
if ($setTheme) {
    Write-Host -Object '  Setting marketplace as current theme...' -ForegroundColor 'Gray'
    Invoke-Spicetify "config" "current_theme" "marketplace"
}

Write-Host -Object '  Creating backup...' -ForegroundColor 'Gray'
$backupResult = Invoke-Spicetify "backup"
if ($LASTEXITCODE -ne 0) {
    Write-Host -Object "Warning: Backup encountered an issue" -ForegroundColor 'Yellow'
}

Write-Host -Object '  Applying changes to Spotify...' -ForegroundColor 'Gray'
$applyResult = Invoke-Spicetify "apply"
if ($LASTEXITCODE -ne 0) {
    Write-Host -Object "Error: Could not apply changes" -ForegroundColor 'Red'
    return
}

Write-Host -Object 'Done!' -ForegroundColor 'Green'
Write-Host -Object 'If nothing has happened, check the messages above for errors'