# Azure Artifacts NuGet Test Project

A test project to validate Azure DevOps Artifacts NuGet feed publishing.

## Quick Start

### 1. Create your `.env` file

Copy the example file and fill in your values:

```powershell
Copy-Item .env.example .env
```

Edit `.env` with your configuration:

```
PAT='your_personal_access_token'
DevOpsOrg='YourOrgName'
FeedName='YourFeedName'
```

**PAT Requirements:** Your PAT must have **Packaging (Read, write & manage)** scope.

### 2. Run Setup

This creates the feed (if needed) and configures NuGet credentials:

```powershell
.\scripts\setup.ps1
```

### 3. Build and Publish

This builds, packs, and pushes with auto-incrementing version:

```powershell
.\scripts\build-and-publish.ps1
```

Run it multiple times - the version auto-increments (1.0.0 → 1.0.1 → 1.0.2).

## Troubleshooting

### 401 Unauthorized
- Check your PAT is valid and not expired
- Ensure PAT has **Packaging (Read, write & manage)** scope
- Verify your organization name is correct

### 403 Forbidden
- You need Contributor permissions on the feed
- Ask your admin to grant access

### Feed already exists
- The setup script handles this automatically - it will skip creation

## Files

| File | Purpose |
|------|---------|
| `.env.example` | Template for configuration |
| `.env` | Your local configuration (not committed) |
| `scripts/setup.ps1` | Creates feed and configures credentials |
| `scripts/build-and-publish.ps1` | Builds, packs, publishes with auto-version |
| `.version` | Tracks current version (not committed) |

## How It Works

1. **setup.ps1** uses the Azure DevOps REST API to create/verify the feed
2. **build-and-publish.ps1** reads version from `.version`, increments it, then runs `dotnet build`, `dotnet pack`, and `dotnet nuget push`
3. The PAT is used for both REST API calls and NuGet authentication

## Creating a PAT

1. Navigate to Azure DevOps: `https://dev.azure.com/<YOUR_ORG>`
2. Click **User Settings** (top right) → **Personal Access Tokens**
3. Click **+ New Token**
4. Configure:
   - **Name**: `NuGet Package Publishing`
   - **Organization**: Select your org
   - **Scopes**: Select **Packaging** → **Read, write & manage**
5. Click **Create** and copy the token
# devops_artifacts
