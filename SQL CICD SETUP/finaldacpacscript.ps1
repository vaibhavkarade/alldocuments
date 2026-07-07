<#
.SYNOPSIS
    DACPAC Auto-Extract & Commit - Keeps Timestamped History
.DESCRIPTION
    Maintains historical DACPAC files with timestamps for deployment tracking
    Always updates _Latest.dacpac to point to newest version
    Auto-installs Git LFS if missing (no sudo required)
.EXAMPLE
    pwsh extract-dacpac-keep-history.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExtractOnly
)

#region Configuration
$CONFIG_UserEmail = "vaibhav_karade@epam.com"
$CONFIG_UserName = "Vaibhav Karade"
$CONFIG_ServerName = "devsqlcicdtest.database.windows.net"
$CONFIG_DefaultDatabase = "devsqlcicddatabase"
$CONFIG_ResourceGroup = "sqlcicd"
$CONFIG_AzureDevOpsOrg = "DevOpsStuffs"
$CONFIG_AzureDevOpsProject = "cicdtestauto"
$CONFIG_RepoName = "sql-cicd-setup"
$CONFIG_TargetBranch = "develop"
$CONFIG_OutputFolder = "DACPACs/DEV"
$CONFIG_WorkspaceRoot = "$HOME/dacpac-workspace"
$CONFIG_LocalRepoPath = "$CONFIG_WorkspaceRoot/$CONFIG_RepoName"
$CONFIG_AutoCommit = $true
$CONFIG_AutoPush = $true
$CONFIG_CommitMessagePrefix = "Auto-update DACPAC"

# File Management Settings
$CONFIG_KeepTimestampedFiles = $true  # ✅ Keep all timestamped files
$CONFIG_KeepLatestFile = $true        # Always maintain a _Latest.dacpac file
$CONFIG_MaxHistoryFiles = 10          # Optional: Keep only last N timestamped files (0 = keep all)

$CONFIG_CreateMetadataFile = $true
$CONFIG_MinimumFileSizeKB = 3
$CONFIG_ValidateStructure = $true

# Git LFS Installation Settings
$CONFIG_GitLfsVersion = "3.4.0"
$CONFIG_GitLfsInstallDir = "$HOME/bin"

# Ensure user bin is in PATH
$env:PATH = "$HOME/bin:$HOME/.dotnet/tools:$env:PATH"
#endregion

#region Banner
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   DACPAC AUTO-EXTRACT & COMMIT (WITH HISTORY)          ║" -ForegroundColor Cyan
Write-Host "║   Azure Cloud Shell Edition v3.5 (FIXED)               ║" -ForegroundColor Cyan
Write-Host "║   Auto-installs Git LFS if missing                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$scriptStartTime = Get-Date

if (-not $DatabaseName) { $DatabaseName = $CONFIG_DefaultDatabase }
if ($ExtractOnly) { $CONFIG_AutoCommit = $false; $CONFIG_AutoPush = $false }
#endregion

#region Verify Azure Login
Write-Host "🔍 Verifying Azure account..." -ForegroundColor Yellow

try {
    $currentAzureUser = az account show --query user.name -o tsv 2>&1
    if ($LASTEXITCODE -eq 0 -and $currentAzureUser) {
        Write-Host "✅ Logged in as: $currentAzureUser" -ForegroundColor Green
        $CONFIG_UserEmail = $currentAzureUser
    }
    else {
        throw "Not logged in"
    }
}
catch {
    Write-Host "❌ Not logged into Azure!" -ForegroundColor Red
    exit 1
}
Write-Host ""
#endregion

#region Configure Git Credentials
Write-Host "🔐 Configuring Git authentication (no password mode)..." -ForegroundColor Yellow

try {
    $devopsExtension = az extension list --query "[?name=='azure-devops'].name" -o tsv 2>&1
    if (-not $devopsExtension) {
        Write-Host "   Installing Azure DevOps extension..." -ForegroundColor Gray
        az extension add --name azure-devops --only-show-errors 2>&1 | Out-Null
    }
    
    az devops configure --defaults organization="https://dev.azure.com/$CONFIG_AzureDevOpsOrg" project="$CONFIG_AzureDevOpsProject" 2>&1 | Out-Null
    
    Write-Host "   Obtaining Azure DevOps token..." -ForegroundColor Gray
    $adoToken = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv 2>&1
    
    if ($LASTEXITCODE -ne 0 -or (-not $adoToken) -or $adoToken -match "ERROR") {
        throw "Failed to get Azure DevOps token"
    }
    
    Write-Host "   Configuring Git credential storage..." -ForegroundColor Gray
    
    git config --global credential.helper store 2>&1 | Out-Null
    git config --global credential.https://dev.azure.com.useHttpPath true 2>&1 | Out-Null
    
    $gitCredentialsPath = "$HOME/.git-credentials"
    $credentialLine = "https://oauth2:$adoToken@dev.azure.com"
    
    $existingCredentials = @()
    if (Test-Path $gitCredentialsPath) {
        $existingCredentials = Get-Content $gitCredentialsPath | Where-Object { $_ -notmatch "dev.azure.com" }
    }
    
    $existingCredentials + $credentialLine | Set-Content $gitCredentialsPath -Force
    bash -c "chmod 600 '$gitCredentialsPath'" 2>&1 | Out-Null
    
    $env:AZURE_DEVOPS_EXT_PAT = $adoToken
    $env:GIT_ASKPASS = "echo"
    
    git config --global user.name "$CONFIG_UserName" 2>&1 | Out-Null
    git config --global user.email "$CONFIG_UserEmail" 2>&1 | Out-Null
    
    $CONFIG_RepoUrl = "https://oauth2:$adoToken@dev.azure.com/$CONFIG_AzureDevOpsOrg/$CONFIG_AzureDevOpsProject/_git/$CONFIG_RepoName"
    
    Write-Host "✅ Git authentication configured (password-free)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to configure Git auth: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""
#endregion

#region Install/Verify Git LFS (Auto-Install if Missing)
Write-Host "🔍 Checking Git LFS installation..." -ForegroundColor Yellow

$gitLfsInstalled = $false
$lfsInstallDir = $CONFIG_GitLfsInstallDir
$lfsBinaryPath = "$lfsInstallDir/git-lfs"

# Update PATH
$env:PATH = "$lfsInstallDir`:$env:PATH"

# Check if Git LFS is already available
$lfsLocations = @(
    "/usr/bin/git-lfs",
    "/usr/local/bin/git-lfs",
    "$lfsBinaryPath"
)

foreach ($location in $lfsLocations) {
    if (Test-Path $location) {
        try {
            $lfsVersion = & $location version 2>&1
            if ($LASTEXITCODE -eq 0 -and $lfsVersion -match "git-lfs") {
                Write-Host "✅ Git LFS found: $lfsVersion" -ForegroundColor Green
                Write-Host "   Location: $location" -ForegroundColor Gray
                $gitLfsInstalled = $true
                $lfsBinaryPath = $location
                break
            }
        }
        catch {
            continue
        }
    }
}

# Try system git-lfs command
if (-not $gitLfsInstalled) {
    try {
        $lfsVersion = git lfs version 2>&1
        if ($LASTEXITCODE -eq 0 -and $lfsVersion -match "git-lfs") {
            Write-Host "✅ Git LFS found in system: $lfsVersion" -ForegroundColor Green
            $gitLfsInstalled = $true
        }
    }
    catch {
        Write-Host "   Git LFS not found in system PATH" -ForegroundColor Gray
    }
}

# Install Git LFS if not found
if (-not $gitLfsInstalled) {
    Write-Host "📦 Installing Git LFS to user directory..." -ForegroundColor Yellow
    Write-Host "   (No sudo required - installing to ~/bin)" -ForegroundColor Gray
    
    try {
        # Create bin directory
        if (-not (Test-Path $lfsInstallDir)) {
            Write-Host "   Creating directory: $lfsInstallDir" -ForegroundColor Gray
            New-Item -ItemType Directory -Path $lfsInstallDir -Force | Out-Null
        }
        
        # Download Git LFS
        $lfsArchive = "git-lfs-linux-amd64-v$CONFIG_GitLfsVersion.tar.gz"
        $lfsUrl = "https://github.com/git-lfs/git-lfs/releases/download/v$CONFIG_GitLfsVersion/$lfsArchive"
        $downloadPath = "$HOME/$lfsArchive"
        
        Write-Host "   Downloading Git LFS v$CONFIG_GitLfsVersion..." -ForegroundColor Gray
        
        # Try curl first (more reliable in Cloud Shell)
        $curlExists = Get-Command curl -ErrorAction SilentlyContinue
        if ($curlExists) {
            Write-Host "   Using curl for download..." -ForegroundColor DarkGray
            bash -c "curl -L -o '$downloadPath' '$lfsUrl'" 2>&1 | Out-Null
        }
        else {
            Write-Host "   Using wget for download..." -ForegroundColor DarkGray
            bash -c "wget -q -O '$downloadPath' '$lfsUrl'" 2>&1 | Out-Null
        }
        
        if (-not (Test-Path $downloadPath)) {
            throw "Download failed - file not created"
        }
        
        $downloadSize = (Get-Item $downloadPath).Length
        if ($downloadSize -lt 100KB) {
            Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
            throw "Downloaded file is too small ($downloadSize bytes)"
        }
        
        Write-Host "   Downloaded: $([math]::Round($downloadSize / 1MB, 2)) MB" -ForegroundColor Gray
        
        # Extract
        Write-Host "   Extracting archive..." -ForegroundColor Gray
        Push-Location $HOME
        
        bash -c "tar -xzf '$lfsArchive'" 2>&1 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Extraction failed"
        }
        
        $extractedDir = "git-lfs-$CONFIG_GitLfsVersion"
        $lfsBinary = "$HOME/$extractedDir/git-lfs"
        
        if (-not (Test-Path $lfsBinary)) {
            throw "Git LFS binary not found after extraction"
        }
        
        # Copy to bin directory
        Write-Host "   Installing to $lfsInstallDir..." -ForegroundColor Gray
        Copy-Item -Path $lfsBinary -Destination $lfsBinaryPath -Force
        
        # Make executable
        bash -c "chmod +x '$lfsBinaryPath'" 2>&1 | Out-Null
        
        # Cleanup
        Write-Host "   Cleaning up..." -ForegroundColor Gray
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $extractedDir -ErrorAction SilentlyContinue
        
        Pop-Location
        
        # Update PATH
        $env:PATH = "$lfsInstallDir`:$env:PATH"
        
        # Update .bashrc for future sessions
        $bashrcPath = "$HOME/.bashrc"
        $pathLine = "export PATH=\$HOME/bin:\$PATH"
        
        $needsUpdate = $true
        if (Test-Path $bashrcPath) {
            $bashrcContent = Get-Content $bashrcPath -Raw
            if ($bashrcContent -match 'HOME/bin.*PATH') {
                $needsUpdate = $false
            }
        }
        
        if ($needsUpdate) {
            Write-Host "   Updating .bashrc for future sessions..." -ForegroundColor Gray
            Add-Content -Path $bashrcPath -Value "`n# Git LFS (added by DACPAC script)`n$pathLine"
        }
        
        # Verify installation
        if (Test-Path $lfsBinaryPath) {
            $lfsCheck = & $lfsBinaryPath version 2>&1
            
            if ($LASTEXITCODE -eq 0 -and $lfsCheck -match "git-lfs") {
                Write-Host "✅ Git LFS installed successfully!" -ForegroundColor Green
                Write-Host "   Version: $lfsCheck" -ForegroundColor Gray
                Write-Host "   Location: $lfsBinaryPath" -ForegroundColor Gray
                $gitLfsInstalled = $true
            }
            else {
                throw "Installation verification failed"
            }
        }
        else {
            throw "Binary not found after installation"
        }
    }
    catch {
        Write-Host "❌ Failed to install Git LFS: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please install Git LFS manually:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Run these commands in Bash:" -ForegroundColor Cyan
        Write-Host "  cd ~" -ForegroundColor Gray
        Write-Host "  curl -L -o git-lfs.tar.gz https://github.com/git-lfs/git-lfs/releases/download/v3.4.0/git-lfs-linux-amd64-v3.4.0.tar.gz" -ForegroundColor Gray
        Write-Host "  tar -xzf git-lfs.tar.gz" -ForegroundColor Gray
        Write-Host "  mkdir -p ~/bin" -ForegroundColor Gray
        Write-Host "  cp git-lfs-3.4.0/git-lfs ~/bin/" -ForegroundColor Gray
        Write-Host "  chmod +x ~/bin/git-lfs" -ForegroundColor Gray
        Write-Host "  export PATH=\$HOME/bin:\$PATH" -ForegroundColor Gray
        Write-Host "  git lfs install" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}

# Initialize Git LFS
Write-Host "   Initializing Git LFS..." -ForegroundColor Gray
$lfsInitOutput = git lfs install 2>&1

if ($LASTEXITCODE -eq 0 -or $lfsInitOutput -match "already") {
    Write-Host "✅ Git LFS ready for use" -ForegroundColor Green
}
else {
    Write-Host "⚠️  Git LFS initialization warning (may still work): $lfsInitOutput" -ForegroundColor Yellow
}

Write-Host ""
#endregion

#region Verify Prerequisites
Write-Host "🔍 Verifying prerequisites..." -ForegroundColor Yellow

$dotnetVersion = dotnet --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ .NET not found" -ForegroundColor Red
    exit 1
}
Write-Host "✅ .NET: $dotnetVersion" -ForegroundColor Green

$sqlPackageExists = $null -ne (Get-Command sqlpackage -ErrorAction SilentlyContinue)
if (-not $sqlPackageExists) {
    Write-Host "❌ SqlPackage not found" -ForegroundColor Red
    exit 1
}
Write-Host "✅ SqlPackage installed" -ForegroundColor Green

$sqlPackageVersion = sqlpackage /version 2>&1 | Select-Object -First 1
Write-Host "   Version: $sqlPackageVersion" -ForegroundColor Gray
Write-Host ""
#endregion

#region Configuration Display
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$dacpacFileName = "$DatabaseName`_$timestamp.dacpac"
$dacpacLatestName = "$DatabaseName`_Latest.dacpac"

Write-Host "📊 Configuration:" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host "  User: $CONFIG_UserEmail" -ForegroundColor Cyan
Write-Host "  Database: $DatabaseName" -ForegroundColor Cyan
Write-Host "  Repository: $CONFIG_RepoName" -ForegroundColor Cyan
Write-Host "  Branch: $CONFIG_TargetBranch" -ForegroundColor Cyan
Write-Host "  Git LFS: ✅ Enabled (auto-installed if needed)" -ForegroundColor Green
Write-Host "  Keep History: ✅ Yes (timestamped files retained)" -ForegroundColor Green
Write-Host "  Max History: $(if($CONFIG_MaxHistoryFiles -gt 0){"$CONFIG_MaxHistoryFiles files"}else{'Unlimited'})" -ForegroundColor Cyan
Write-Host "  Authentication: 🔐 Token-based (no password)" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host ""
#endregion

#region Setup Repository
if ($CONFIG_AutoCommit) {
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║              REPOSITORY SETUP                          ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    
    if (-not (Test-Path $CONFIG_WorkspaceRoot)) {
        New-Item -ItemType Directory -Path $CONFIG_WorkspaceRoot -Force | Out-Null
    }
    
    if (Test-Path $CONFIG_LocalRepoPath) {
        Write-Host "✅ Repository exists - updating..." -ForegroundColor Green
        
        Push-Location $CONFIG_LocalRepoPath
        
        Write-Host "   Updating remote URL with token..." -ForegroundColor Gray
        git remote set-url origin $CONFIG_RepoUrl 2>&1 | Out-Null
        
        git config user.name "$CONFIG_UserName" 2>&1 | Out-Null
        git config user.email "$CONFIG_UserEmail" 2>&1 | Out-Null
        git fetch origin 2>&1 | Out-Null
        git reset --hard 2>&1 | Out-Null
        git clean -fd 2>&1 | Out-Null
        
        $currentBranch = git branch --show-current 2>&1
        if ($currentBranch -ne $CONFIG_TargetBranch) {
            $remoteBranchExists = git branch -r --list "origin/$CONFIG_TargetBranch" 2>&1
            if ($remoteBranchExists) {
                git checkout $CONFIG_TargetBranch 2>&1 | Out-Null
                git reset --hard "origin/$CONFIG_TargetBranch" 2>&1 | Out-Null
            }
            else {
                git checkout -b $CONFIG_TargetBranch 2>&1 | Out-Null
            }
        }
        else {
            git pull origin $CONFIG_TargetBranch 2>&1 | Out-Null
        }
        
        Pop-Location
        Write-Host "✅ Repository updated" -ForegroundColor Green
    }
    else {
        Write-Host "📥 Cloning repository..." -ForegroundColor Yellow
        
        Push-Location $CONFIG_WorkspaceRoot
        
        $cloneOutput = git clone $CONFIG_RepoUrl $CONFIG_RepoName 2>&1
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $CONFIG_LocalRepoPath)) {
            Write-Host "✅ Repository cloned" -ForegroundColor Green
            
            Push-Location $CONFIG_LocalRepoPath
            
            git config user.name "$CONFIG_UserName" 2>&1 | Out-Null
            git config user.email "$CONFIG_UserEmail" 2>&1 | Out-Null
            
            $defaultBranch = git branch --show-current 2>&1
            
            if ($defaultBranch -ne $CONFIG_TargetBranch) {
                $remoteBranchExists = git branch -r --list "origin/$CONFIG_TargetBranch" 2>&1
                
                if ($remoteBranchExists) {
                    git checkout -b $CONFIG_TargetBranch "origin/$CONFIG_TargetBranch" 2>&1 | Out-Null
                }
                else {
                    git checkout -b $CONFIG_TargetBranch 2>&1 | Out-Null
                }
            }
            
            Pop-Location
            Pop-Location
            Write-Host "✅ Repository configured" -ForegroundColor Green
        }
        else {
            Pop-Location
            Write-Host "❌ Failed to clone repository" -ForegroundColor Red
            Write-Host "   Error: $cloneOutput" -ForegroundColor Gray
            exit 1
        }
    }
    
    # Configure Git LFS
    Write-Host ""
    Write-Host "🔧 Configuring Git LFS for repository..." -ForegroundColor Yellow
    
    Push-Location $CONFIG_LocalRepoPath
    
    $gitattributesPath = ".gitattributes"
    $needsLfsConfig = $true
    
    if (Test-Path $gitattributesPath) {
        $gitattributesContent = Get-Content $gitattributesPath -Raw
        if ($gitattributesContent -like "*dacpac*filter=lfs*") {
            $needsLfsConfig = $false
        }
    }
    
    if ($needsLfsConfig) {
        Write-Host "   Adding LFS tracking for *.dacpac..." -ForegroundColor Gray
        git lfs track "*.dacpac" 2>&1 | Out-Null
        git lfs track "$CONFIG_OutputFolder/*.dacpac" 2>&1 | Out-Null
        
        git add .gitattributes 2>&1 | Out-Null
        
        $hasChanges = git diff --cached --name-only | Where-Object { $_ -eq ".gitattributes" }
        if ($hasChanges) {
            git commit -m "Configure Git LFS for DACPAC files" 2>&1 | Out-Null
            Write-Host "✅ LFS configured and committed" -ForegroundColor Green
        }
    }
    else {
        Write-Host "✅ LFS already configured" -ForegroundColor Green
    }
    
    # Show LFS tracking status
    $lfsPatterns = git lfs track 2>&1
    $dacpacPatterns = $lfsPatterns | Where-Object { $_ -like "*.dacpac*" }
    if ($dacpacPatterns) {
        Write-Host "   Tracking patterns:" -ForegroundColor Gray
        $dacpacPatterns | ForEach-Object {
            Write-Host "     $_" -ForegroundColor DarkGray
        }
    }
    
    Pop-Location
    
    Write-Host ""
}
#endregion

#region Setup Output Folder
if ($CONFIG_AutoCommit) {
    $fullOutputPath = Join-Path $CONFIG_LocalRepoPath $CONFIG_OutputFolder
}
else {
    $fullOutputPath = "./$CONFIG_OutputFolder"
}

if (-not (Test-Path $fullOutputPath)) {
    New-Item -ItemType Directory -Path $fullOutputPath -Force | Out-Null
}

$dacpacPath = Join-Path $fullOutputPath $dacpacFileName
$dacpacLatestPath = Join-Path $fullOutputPath $dacpacLatestName
#endregion

#region Get SQL Token & Extract
Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              EXTRACTING DACPAC                         ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

# Show existing DACPAC files (instead of deleting)
if ($CONFIG_AutoCommit -and $CONFIG_KeepTimestampedFiles) {
    $existingDacpacs = Get-ChildItem $fullOutputPath -Filter "$DatabaseName`_*.dacpac" -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -ne "$DatabaseName`_Latest.dacpac" } |
        Sort-Object LastWriteTime -Descending
    
    if ($existingDacpacs) {
        Write-Host "📚 Existing DACPAC files ($($existingDacpacs.Count)):" -ForegroundColor Yellow
        
        $existingDacpacs | Select-Object -First 5 | ForEach-Object {
            $sizeMB = [math]::Round($_.Length / 1MB, 2)
            $age = (Get-Date) - $_.LastWriteTime
            $ageStr = if ($age.Days -gt 0) { "$($age.Days)d ago" } elseif ($age.Hours -gt 0) { "$($age.Hours)h ago" } else { "$($age.Minutes)m ago" }
            Write-Host "   📄 $($_.Name) ($sizeMB MB) - $ageStr" -ForegroundColor Cyan
        }
        
        if ($existingDacpacs.Count -gt 5) {
            Write-Host "   ... and $($existingDacpacs.Count - 5) more file(s)" -ForegroundColor Gray
        }
        Write-Host ""
        
        # Optional: Clean up old files if max history is set
        if ($CONFIG_MaxHistoryFiles -gt 0 -and $existingDacpacs.Count -ge $CONFIG_MaxHistoryFiles) {
            $filesToDelete = $existingDacpacs | Select-Object -Skip ($CONFIG_MaxHistoryFiles - 1)
            
            if ($filesToDelete) {
                Write-Host "🧹 Removing old files (keeping last $CONFIG_MaxHistoryFiles):" -ForegroundColor Yellow
                $filesToDelete | ForEach-Object {
                    Write-Host "   🗑️  $($_.Name)" -ForegroundColor Gray
                    Remove-Item $_.FullName -Force
                }
                Write-Host "✅ Old files cleaned up" -ForegroundColor Green
                Write-Host ""
            }
        }
    }
    else {
        Write-Host "📚 No existing DACPAC files found (this is the first extraction)" -ForegroundColor Gray
        Write-Host ""
    }
}

# Get SQL token
Write-Host "🔐 Getting Azure SQL access token..." -ForegroundColor Yellow
$accessToken = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>&1

if ($LASTEXITCODE -ne 0 -or (-not $accessToken)) {
    Write-Host "❌ Failed to get SQL access token" -ForegroundColor Red
    exit 1
}
Write-Host "✅ SQL token obtained" -ForegroundColor Green
Write-Host ""

$connectionString = "Server=$CONFIG_ServerName;Database=$DatabaseName;Encrypt=True;"

Write-Host "⏳ Extracting from $DatabaseName..." -ForegroundColor Yellow
Write-Host "   Output file: $dacpacFileName" -ForegroundColor Gray
Write-Host "   (This may take a few minutes)" -ForegroundColor Gray
Write-Host ""

$extractStartTime = Get-Date
$extractionSuccessful = $false
$tables = 0; $views = 0; $procs = 0; $functions = 0

try {
    $extractOutput = sqlpackage `
        /Action:Extract `
        /TargetFile:"$dacpacPath" `
        /p:ExtractAllTableData=False `
        /p:VerifyExtraction=True `
        /p:ExtractReferencedServerScopedElements=True `
        /p:ExtractApplicationScopedObjectsOnly=True `
        /SourceConnectionString:"$connectionString" `
        /AccessToken:"$accessToken" `
        2>&1
    
    if ($LASTEXITCODE -eq 0 -and (Test-Path $dacpacPath)) {
        $extractEndTime = Get-Date
        $duration = ($extractEndTime - $extractStartTime).TotalSeconds
        
        $fileInfo = Get-Item $dacpacPath
        $fileSizeBytes = $fileInfo.Length
        $fileSizeMB = [math]::Round($fileSizeBytes / 1MB, 2)
        $fileSizeKB = [math]::Round($fileSizeBytes / 1KB, 2)
        
        # Validate structure
        $isValid = $false
        
        try {
            Add-Type -Assembly System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($dacpacPath)
            
            $hasModel = $zip.Entries | Where-Object { $_.Name -eq "model.xml" }
            $hasOrigin = $zip.Entries | Where-Object { $_.Name -eq "Origin.xml" }
            
            if ($hasModel -and $hasOrigin) {
                $modelEntry = $zip.Entries | Where-Object { $_.Name -eq "model.xml" }
                $reader = New-Object System.IO.StreamReader($modelEntry.Open())
                $modelXml = $reader.ReadToEnd()
                $reader.Close()
                
                [xml]$model = $modelXml
                $tables = ($model.DataSchemaModel.Model.Element | Where-Object { $_.Type -like '*Table*' }).Count
                $views = ($model.DataSchemaModel.Model.Element | Where-Object { $_.Type -like '*View*' }).Count
                $procs = ($model.DataSchemaModel.Model.Element | Where-Object { $_.Type -like '*Procedure*' }).Count
                $functions = ($model.DataSchemaModel.Model.Element | Where-Object { $_.Type -like '*Function*' }).Count
                
                $totalObjects = $tables + $views + $procs + $functions
                
                if ($totalObjects -gt 0) {
                    $isValid = $true
                }
            }
            
            $zip.Dispose()
        }
        catch {
            Write-Host "⚠️  Could not validate DACPAC structure: $_" -ForegroundColor Yellow
        }
        
        if ($isValid) {
            Write-Host "✅ DACPAC EXTRACTED SUCCESSFULLY!" -ForegroundColor Green
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
            Write-Host "📄 File: $($fileInfo.Name)" -ForegroundColor Cyan
            Write-Host "📦 Size: $fileSizeMB MB ($fileSizeKB KB)" -ForegroundColor Cyan
            Write-Host "⏱️  Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Cyan
            Write-Host "📁 Location: $fullOutputPath" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "📊 Schema Objects:" -ForegroundColor Yellow
            Write-Host "   Tables: $tables | Views: $views | Procs: $procs | Functions: $functions" -ForegroundColor Cyan
            Write-Host "   Total: $($tables + $views + $procs + $functions)" -ForegroundColor Cyan
            Write-Host ""
            
            $extractionSuccessful = $true
            
            # Copy to Latest (always update the Latest file)
            if ($CONFIG_KeepLatestFile) {
                Write-Host "💾 Updating Latest version..." -ForegroundColor Yellow
                Copy-Item -Path $dacpacPath -Destination $dacpacLatestPath -Force
                Write-Host "✅ Updated: $dacpacLatestName" -ForegroundColor Green
                Write-Host ""
            }
            
            # Show all DACPAC files in repository
            Write-Host "📂 All DACPAC files in repository:" -ForegroundColor Yellow
            $allDacpacs = Get-ChildItem $fullOutputPath -Filter "*.dacpac" | Sort-Object LastWriteTime -Descending
            foreach ($file in $allDacpacs) {
                $size = [math]::Round($file.Length / 1MB, 2)
                $isLatest = ($file.Name -eq $dacpacLatestName)
                $isNew = ($file.Name -eq $dacpacFileName)
                $marker = if ($isNew) { "🆕" } elseif ($isLatest) { "📌" } else { "📄" }
                $label = if ($isNew) { " (NEW)" } elseif ($isLatest) { " (LATEST)" } else { "" }
                Write-Host "   $marker $($file.Name) ($size MB)$label" -ForegroundColor $(if($isNew){'Green'}elseif($isLatest){'Cyan'}else{'Gray'})
            }
            Write-Host ""
            
            # Save metadata
            if ($CONFIG_CreateMetadataFile) {
                $metadata = @{
                    Extraction = @{
                        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        TimestampUTC = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
                        DurationSeconds = [math]::Round($duration, 2)
                        ExtractedBy = $CONFIG_UserEmail
                        ExtractedFrom = "Azure Cloud Shell"
                    }
                    Database = @{
                        Name = $DatabaseName
                        Server = $CONFIG_ServerName
                        ResourceGroup = $CONFIG_ResourceGroup
                    }
                    Files = @{
                        DacpacFile = $dacpacFileName
                        LatestFile = $dacpacLatestName
                        SizeMB = $fileSizeMB
                        SizeKB = $fileSizeKB
                        SizeBytes = $fileSizeBytes
                        HistoryRetained = $CONFIG_KeepTimestampedFiles
                        TotalHistoricalFiles = $allDacpacs.Count
                    }
                    Schema = @{
                        Tables = $tables
                        Views = $views
                        StoredProcedures = $procs
                        Functions = $functions
                        TotalObjects = ($tables + $views + $procs + $functions)
                    }
                    Repository = @{
                        Organization = $CONFIG_AzureDevOpsOrg
                        Project = $CONFIG_AzureDevOpsProject
                        Name = $CONFIG_RepoName
                        Branch = $CONFIG_TargetBranch
                    }
                    GitLFS = @{
                        Enabled = $true
                        Tracked = "*.dacpac"
                        AutoInstall = $true
                    }
                } | ConvertTo-Json -Depth 10
                
                $metadataFile = Join-Path $fullOutputPath "$DatabaseName`_metadata.json"
                $metadata | Out-File -FilePath $metadataFile -Encoding UTF8 -Force
                
                Write-Host "✅ Metadata saved: $DatabaseName`_metadata.json" -ForegroundColor Green
                Write-Host ""
            }
        }
        else {
            throw "DACPAC validation failed - no objects found"
        }
    }
    else {
        throw "SqlPackage extraction failed"
    }
}
catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
    exit 1
}
#endregion

#region Commit and Push
if ($extractionSuccessful -and $CONFIG_AutoCommit) {
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║              COMMITTING TO AZURE REPOS                 ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    
    Push-Location $CONFIG_LocalRepoPath
    
    # Verify remote URL has token
    $remoteUrl = git remote get-url origin 2>&1
    if ($remoteUrl -notlike "*oauth2*") {
        Write-Host "   Updating remote URL with authentication token..." -ForegroundColor Gray
        git remote set-url origin $CONFIG_RepoUrl 2>&1 | Out-Null
    }
    
    Write-Host "📝 Staging files..." -ForegroundColor Yellow
    git add "$CONFIG_OutputFolder/*" 2>&1 | Out-Null
    
    $stagedFiles = git diff --cached --name-only
    
    if ($stagedFiles) {
        Write-Host "✅ Staged $($stagedFiles.Count) file(s):" -ForegroundColor Green
        
        foreach ($file in $stagedFiles) {
            $fileSize = (Get-Item (Join-Path $CONFIG_LocalRepoPath $file)).Length
            $fileSizeMBDisplay = [math]::Round($fileSize / 1MB, 2)
            Write-Host "   📄 $file ($fileSizeMBDisplay MB)" -ForegroundColor Cyan
        }
        Write-Host ""
        
        # Count total historical files
        $totalDacpacFiles = (Get-ChildItem $fullOutputPath -Filter "*.dacpac").Count
        
        $commitMessage = @"
$CONFIG_CommitMessagePrefix - $DatabaseName

Database: $DatabaseName
Schema: $tables tables, $views views, $procs procs, $functions functions
Size: $fileSizeMB MB ($fileSizeKB KB)
Duration: $([math]::Round($duration, 2))s

Timestamped File: $dacpacFileName
Latest File: $dacpacLatestName
Total Historical Files: $totalDacpacFiles

Extracted: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
By: $CONFIG_UserEmail
From: Azure Cloud Shell
Branch: $CONFIG_TargetBranch

✅ Timestamped files are retained for deployment tracking
"@
        
        Write-Host "💾 Committing..." -ForegroundColor Yellow
        git commit -m "$commitMessage" 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            $commitHash = git rev-parse --short HEAD
            Write-Host "✅ Committed: $commitHash" -ForegroundColor Green
            Write-Host ""
            
            # Verify LFS tracking
            Write-Host "🔍 Verifying Git LFS tracking..." -ForegroundColor Yellow
            $lfsFiles = git lfs ls-files 2>&1
            $dacpacInLFS = $lfsFiles | Where-Object { $_ -like "*dacpac*" }
            
            if ($dacpacInLFS) {
                Write-Host "✅ DACPAC files tracked in Git LFS:" -ForegroundColor Green
                $dacpacInLFS | Select-Object -First 3 | ForEach-Object {
                    Write-Host "   $_" -ForegroundColor Cyan
                }
                if ($dacpacInLFS.Count -gt 3) {
                    Write-Host "   ... and $($dacpacInLFS.Count - 3) more file(s)" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "⚠️  Warning: DACPAC files might not be in LFS" -ForegroundColor Yellow
            }
            Write-Host ""
            
            if ($CONFIG_AutoPush) {
                Write-Host "⬆️  Pushing to Azure DevOps..." -ForegroundColor Yellow
                Write-Host "   (Using token authentication - no password needed)" -ForegroundColor Gray
                Write-Host ""
                
                # Push LFS objects first
                Write-Host "   📦 Pushing LFS objects..." -ForegroundColor Gray
                $lfsPushOutput = git lfs push origin $CONFIG_TargetBranch 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "   ✅ LFS objects pushed" -ForegroundColor Green
                }
                else {
                    Write-Host "   ⚠️  LFS push warning (objects may already exist)" -ForegroundColor Yellow
                }
                
                # Push commit
                Write-Host "   📤 Pushing commit..." -ForegroundColor Gray
                $pushOutput = git push origin $CONFIG_TargetBranch 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ PUSHED SUCCESSFULLY!" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
                    Write-Host "║          ✅ COMPLETED SUCCESSFULLY ✅                 ║" -ForegroundColor Green
                    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "📊 Summary:" -ForegroundColor Yellow
                    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
                    Write-Host "   Database: $DatabaseName" -ForegroundColor Cyan
                    Write-Host "   Objects: $($tables + $views + $procs + $functions)" -ForegroundColor Cyan
                    Write-Host "   New File: $dacpacFileName" -ForegroundColor Green
                    Write-Host "   Size: $fileSizeMB MB ($fileSizeKB KB)" -ForegroundColor Cyan
                    Write-Host "   Latest File: $dacpacLatestName" -ForegroundColor Cyan
                    Write-Host "   Total Historical Files: $totalDacpacFiles" -ForegroundColor Cyan
                    Write-Host "   Commit: $commitHash" -ForegroundColor Cyan
                    Write-Host "   Branch: $CONFIG_TargetBranch" -ForegroundColor Cyan
                    Write-Host "   Duration: $([math]::Round(((Get-Date) - $scriptStartTime).TotalMinutes, 2)) min" -ForegroundColor Cyan
                    Write-Host "   Git LFS: ✅ Enabled (auto-install)" -ForegroundColor Green
                    Write-Host "   History: ✅ Retained (timestamped files kept)" -ForegroundColor Green
                    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "🔗 View in Azure DevOps:" -ForegroundColor Yellow
                    Write-Host "   https://dev.azure.com/$CONFIG_AzureDevOpsOrg/$CONFIG_AzureDevOpsProject/_git/$CONFIG_RepoName?version=GB$CONFIG_TargetBranch&path=/$CONFIG_OutputFolder" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "💡 Deployment Tips:" -ForegroundColor Yellow
                    Write-Host "   • Use $dacpacLatestName for latest version" -ForegroundColor White
                    Write-Host "   • Use timestamped files for specific version deployments" -ForegroundColor White
                    Write-Host "   • All files are version-controlled in Git with LFS" -ForegroundColor White
                    Write-Host ""
                }
                else {
                    Write-Host "❌ Push failed" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Push output:" -ForegroundColor Yellow
                    $pushOutput | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
                }
            }
        }
        else {
            Write-Host "❌ Commit failed" -ForegroundColor Red
        }
    }
    else {
        Write-Host "ℹ️  No changes detected - files are up to date" -ForegroundColor Cyan
    }
    
    Pop-Location
}
elseif ($extractionSuccessful) {
    Write-Host "✅ Extraction complete (auto-commit disabled)" -ForegroundColor Green
}
#endregion

Write-Host ""
Write-Host "✨ Done!" -ForegroundColor Green
Write-Host ""