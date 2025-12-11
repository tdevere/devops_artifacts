# build-and-publish.ps1 - Builds, packs, and publishes with auto-incrementing version
# Reads configuration from .env file

$ErrorActionPreference = "Stop"

# Load .env file
$envFile = Join-Path $PSScriptRoot "..\\.env"
if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: .env file not found at $envFile"
    Write-Host "Copy .env.example to .env and fill in your values"
    exit 1
}

# Parse .env file
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim().Trim("'").Trim('"')
        Set-Variable -Name $key -Value $value -Scope Script
    }
}

# Project paths
$projectRoot = Join-Path $PSScriptRoot ".."
$projectFile = Join-Path $projectRoot "src\AutomationToolsCore.csproj"
$versionFile = Join-Path $projectRoot ".version"
$feedUrl = "https://pkgs.dev.azure.com/$DevOpsOrg/_packaging/$FeedName/nuget/v3/index.json"

Write-Host "=== Build and Publish ==="
Write-Host "Organization: $DevOpsOrg"
Write-Host "Feed: $FeedName"
Write-Host ""

# Setup auth header for REST API
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
$headers = @{ Authorization = "Basic $base64Auth" }

# Get latest version from feed
Write-Host "Checking latest version in feed..."
$packageUrl = "https://feeds.dev.azure.com/$DevOpsOrg/_apis/packaging/feeds/$FeedName/packages?packageNameQuery=AutomationToolsCore&api-version=7.1-preview.1"
try {
    $response = Invoke-RestMethod -Uri $packageUrl -Headers $headers -Method Get
    $package = $response.value | Where-Object { $_.name -eq "AutomationToolsCore" }
    if ($package) {
        $latestVersion = $package.versions[0].version
        Write-Host "Latest version in feed: $latestVersion"
        $versionParts = $latestVersion.Split('.')
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]
        $patch = [int]$versionParts[2] + 1
    } else {
        Write-Host "Package not found in feed, starting at 1.0.0"
        $major = 1; $minor = 0; $patch = 0
    }
} catch {
    Write-Host "Could not query feed, checking local version file..."
    if (Test-Path $versionFile) {
        $versionParts = (Get-Content $versionFile).Split('.')
        $major = [int]$versionParts[0]
        $minor = [int]$versionParts[1]
        $patch = [int]$versionParts[2] + 1
    } else {
        $major = 1; $minor = 0; $patch = 0
    }
}

$version = "$major.$minor.$patch"
Write-Host "New version: $version"

# Save new version locally
$version | Out-File -FilePath $versionFile -NoNewline

# Clean previous builds
Write-Host ""
Write-Host "--- Cleaning ---"
$binPath = Join-Path $projectRoot "src\bin"
$objPath = Join-Path $projectRoot "src\obj"
if (Test-Path $binPath) { Remove-Item -Recurse -Force $binPath }
if (Test-Path $objPath) { Remove-Item -Recurse -Force $objPath }
Write-Host "Cleaned bin and obj folders"

# Build
Write-Host ""
Write-Host "--- Building ---"
dotnet build $projectFile -c Release
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Build failed"
    exit 1
}
Write-Host "Build succeeded"

# Pack
Write-Host ""
Write-Host "--- Packing ---"
dotnet pack $projectFile -c Release /p:Version=$version --no-build
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Pack failed"
    exit 1
}
Write-Host "Pack succeeded"

# Find the package file
$packagePath = Join-Path $projectRoot "src\bin\Release\AutomationToolsCore.$version.nupkg"
if (-not (Test-Path $packagePath)) {
    Write-Host "ERROR: Package not found at $packagePath"
    exit 1
}
Write-Host "Package: $packagePath"

# Push
Write-Host ""
Write-Host "--- Pushing ---"

# Ensure NuGet source is configured with credentials
$sourceExists = dotnet nuget list source 2>&1 | Select-String -Pattern $FeedName -Quiet
if (-not $sourceExists) {
    Write-Host "Adding NuGet source..."
    dotnet nuget add source $feedUrl --name $FeedName --username az --password $PAT --store-password-in-clear-text 2>&1 | Out-Null
} else {
    Write-Host "Updating NuGet source credentials..."
    dotnet nuget update source $FeedName --source $feedUrl --username az --password $PAT --store-password-in-clear-text 2>&1 | Out-Null
}

dotnet nuget push $packagePath --source $FeedName --api-key az --skip-duplicate
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Push failed"
    exit 1
}

Write-Host ""
Write-Host "=== Success ==="
Write-Host "Published AutomationToolsCore v$version to $FeedName"
