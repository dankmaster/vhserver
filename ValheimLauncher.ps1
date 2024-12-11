$ErrorActionPreference = "Stop"

# Define paths and URLs
$GithubZipUrl = "https://github.com/dankmaster/vhserver/raw/refs/heads/main/plugins.zip" # Replace with the correct direct download link to the zip file
$TempFolderPath = "$env:TEMP\ValheimMods"
$TempZipPath = "$TempFolderPath\mods.zip"
$ExtractedTempPath = "$TempFolderPath\mods_extracted"
$TempChecksumPath = "$TempFolderPath\checksum.txt"
$SteamAppID = "892970"  # Valheim's Steam App ID

# Ensure temp folder exists
if (-not (Test-Path $TempFolderPath)) {
    New-Item -ItemType Directory -Path $TempFolderPath | Out-Null
}

# Function to locate Steam installation dynamically
function Get-SteamPath {
    Write-Host "Locating Steam installation..."

    # Check common registry keys for Steam installation path
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKLM:\SOFTWARE\Wow6432Node\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )

    foreach ($RegPath in $RegistryPaths) {
        try {
            $InstallPath = (Get-ItemProperty -Path $RegPath).InstallPath
            if (Test-Path $InstallPath) {
                return $InstallPath
            }
        } catch {
            # Ignore errors and continue
        }
    }

    Write-Error "Steam installation not found. Please ensure Steam is installed."
    exit 1
}

# Function to locate the Valheim plugins folder dynamically
function Get-PluginsFolder {
    $SteamPath = Get-SteamPath
    $SteamLibraryFolders = Join-Path -Path $SteamPath -ChildPath "steamapps\libraryfolders.vdf"

    if (Test-Path $SteamLibraryFolders) {
        $LibraryContent = Get-Content -Path $SteamLibraryFolders -Raw

        # Extract library paths by identifying "path" entries
        $LibraryPaths = ($LibraryContent -split "`n") |
            ForEach-Object {
                if ($_ -match '"path"\s*"([^"]+)"') {
                    $matches[1]
                }
            } |
            Where-Object { $_ -ne $null }

        foreach ($Path in $LibraryPaths) {
            $PluginsPath = Join-Path -Path $Path -ChildPath "steamapps\common\Valheim\BepInEx\plugins"
            if (Test-Path $PluginsPath) {
                return $PluginsPath
            }
        }
    }

    Write-Error "Valheim installation not found. Please ensure the game is installed via Steam."
    exit 1
}

$PluginsFolder = Get-PluginsFolder

# Function to calculate folder checksum
function Get-FolderChecksum {
    param (
        [string]$FolderPath
    )

    $Files = Get-ChildItem -Path $FolderPath -Recurse | Where-Object { -not $_.PSIsContainer }
    $CombinedHashes = foreach ($File in $Files) {
        Get-FileHash -Path $File.FullName -Algorithm SHA256 | Select-Object -ExpandProperty Hash
    }

    $CombinedHashes -join "" | Set-Content -Path $TempChecksumPath
    return Get-FileHash -Path $TempChecksumPath -Algorithm SHA256 | Select-Object -ExpandProperty Hash
}

# Function to check if an update is needed
function Test-UpdateNeeded {
    Write-Verbose "Downloading mods for checksum verification..."
    Invoke-WebRequest -Uri $GithubZipUrl -OutFile $TempZipPath

    if (Test-Path $ExtractedTempPath) {
        Remove-Item -Path $ExtractedTempPath -Recurse -Force
    }
    Expand-Archive -Path $TempZipPath -DestinationPath $ExtractedTempPath

    $RemoteChecksum = Get-FolderChecksum -FolderPath $ExtractedTempPath
    $LocalChecksum = Get-FolderChecksum -FolderPath $PluginsFolder

    if ($LocalChecksum -ne $RemoteChecksum) {
        Write-Host "Checksum mismatch. Update required."
        return $true
    }

    Write-Host "No update required."
    return $false
}

# Function to download and extract the ZIP
function Update-Mods {
    Write-Host "Removing old plugins..."
    Get-ChildItem -Path $PluginsFolder -Recurse | Remove-Item -Force -Recurse

    Write-Host "Extracting mods..."
    Copy-Item -Path "$ExtractedTempPath\*" -Destination $PluginsFolder -Recurse -Force

    Write-Host "Mods updated."
}

# Main logic
if (Test-UpdateNeeded) {
    Update-Mods
}

Write-Host "Launching Valheim..."
Start-Process -FilePath "steam://rungameid/$SteamAppID"

# Clean up
if (Test-Path $TempZipPath) {
    Remove-Item $TempZipPath
}
if (Test-Path $ExtractedTempPath) {
    Remove-Item -Path $ExtractedTempPath -Recurse -Force
}
if (Test-Path $TempChecksumPath) {
    Remove-Item -Path $TempChecksumPath -Force
}
if (Test-Path $TempFolderPath) {
    Remove-Item -Path $TempFolderPath -Recurse -Force
}
