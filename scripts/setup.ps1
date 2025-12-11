# setup.ps1 - Creates Azure DevOps feed if it doesn't exist
# Reads configuration from .env file

$ErrorActionPreference = "Stop"

# Load .env file
$envFile = Join-Path $PSScriptRoot "..\\.env"
if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: .env file not found at $envFile"
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

Write-Host "=== Azure DevOps Feed Setup ==="
Write-Host "Organization: $DevOpsOrg"
Write-Host "Feed Name: $FeedName"
Write-Host ""

# Setup auth header for REST API
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
$headers = @{ Authorization = "Basic $base64Auth" }

# Check if feed exists using REST API
Write-Host "Checking if feed '$FeedName' exists..."
$feedsUrl = "https://feeds.dev.azure.com/$DevOpsOrg/_apis/packaging/feeds?api-version=7.1-preview.1"

try {
    $response = Invoke-RestMethod -Uri $feedsUrl -Headers $headers -Method Get
    $existingFeed = $response.value | Where-Object { $_.name -eq $FeedName }
    
    if ($existingFeed) {
        Write-Host "Feed '$FeedName' already exists. Skipping creation."
    } else {
        Write-Host "Creating feed '$FeedName'..."
        $createUrl = "https://feeds.dev.azure.com/$DevOpsOrg/_apis/packaging/feeds?api-version=7.1-preview.1"
        $body = @{
            name = $FeedName
            description = "NuGet feed for $FeedName"
            hideDeletedPackageVersions = $true
            upstreamEnabled = $true
        } | ConvertTo-Json
        
        $newFeed = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Post -Body $body -ContentType "application/json"
        Write-Host "Feed '$FeedName' created successfully."
    }
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401) {
        Write-Host "ERROR: Unauthorized. Check your PAT has 'Packaging (Read, write & manage)' scope."
    } elseif ($statusCode -eq 403) {
        Write-Host "ERROR: Forbidden. You don't have permission to manage feeds."
    } else {
        Write-Host "ERROR: $($_.Exception.Message)"
    }
    exit 1
}

# Feed URL
$feedUrl = "https://pkgs.dev.azure.com/$DevOpsOrg/_packaging/$FeedName/nuget/v3/index.json"
Write-Host ""
Write-Host "Feed URL: $feedUrl"
Write-Host ""

# Configure NuGet source credentials
Write-Host "Configuring NuGet credentials..."
$removeResult = dotnet nuget remove source $FeedName 2>&1
$addResult = dotnet nuget add source $feedUrl --name $FeedName --username az --password $PAT --store-password-in-clear-text 2>&1
if ($LASTEXITCODE -ne 0) {
    if ($addResult -match "already exists") {
        Write-Host "NuGet source already configured. Updating..."
        dotnet nuget update source $FeedName --source $feedUrl --username az --password $PAT --store-password-in-clear-text
    } else {
        Write-Host "ERROR: Failed to configure NuGet source"
        Write-Host $addResult
        exit 1
    }
}

Write-Host ""
Write-Host "=== Setup Complete ==="
Write-Host "Run: .\scripts\build-and-publish.ps1"
