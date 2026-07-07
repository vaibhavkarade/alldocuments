# Complete SqlPackage Setup for Cloud Shell
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         SQLPACKAGE INSTALLATION                        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Clean up any broken installations
Write-Host "🧹 Cleaning up..." -ForegroundColor Yellow
dotnet tool uninstall -g microsoft.sqlpackage 2>&1 | Out-Null

# Method 1: Try standalone SqlPackage (works without .NET runtime issues)
Write-Host "📦 Installing standalone SqlPackage..." -ForegroundColor Yellow

$sqlPackageDir = "$HOME/sqlpackage"

if (-not (Test-Path $sqlPackageDir)) {
    New-Item -ItemType Directory -Path $sqlPackageDir -Force | Out-Null
}

try {
    $downloadUrl = "https://aka.ms/sqlpackage-linux"
    $zipFile = "$sqlPackageDir/sqlpackage.zip"
    
    Write-Host "   Downloading (this may take 1-2 minutes)..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing
    
    Write-Host "   Extracting..." -ForegroundColor Gray
    Expand-Archive -Path $zipFile -DestinationPath $sqlPackageDir -Force
    
    # Make executable
    bash -c "chmod +x $sqlPackageDir/sqlpackage"
    
    # Update PATH for current session
    $env:PATH = "$sqlPackageDir`:$env:PATH"
    
    Write-Host "   Verifying installation..." -ForegroundColor Gray
    Start-Sleep -Seconds 1
    
    $version = & "$sqlPackageDir/sqlpackage" /version 2>&1 | Select-Object -First 1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ SqlPackage installed successfully!" -ForegroundColor Green
        Write-Host "   Version: $version" -ForegroundColor Gray
        Write-Host "   Location: $sqlPackageDir/sqlpackage" -ForegroundColor Gray
        Write-Host ""
        
        # Add to PowerShell profile
        $profileContent = "`$env:PATH = `"$sqlPackageDir`:$env:PATH`""
        $profilePath = "$HOME/.config/PowerShell/Microsoft.PowerShell_profile.ps1"
        
        $profileDir = Split-Path $profilePath -Parent
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        
        if (Test-Path $profilePath) {
            $existingProfile = Get-Content $profilePath -Raw
            if ($existingProfile -notmatch [regex]::Escape('sqlpackage')) {
                Add-Content -Path $profilePath -Value "`n# SqlPackage Path"
                Add-Content -Path $profilePath -Value $profileContent
            }
        } else {
            "# SqlPackage Path`n$profileContent" | Out-File -FilePath $profilePath -Encoding UTF8
        }
        
        Write-Host "✅ Configuration saved for future sessions" -ForegroundColor Green
        Write-Host ""
        Write-Host "🎉 Ready to use! Run your DACPAC extraction script now." -ForegroundColor Green
        Write-Host ""
        
    } else {
        throw "SqlPackage verification failed"
    }
    
} catch {
    Write-Host ""
    Write-Host "❌ Installation failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please try manual installation:" -ForegroundColor Yellow
    Write-Host "  wget https://aka.ms/sqlpackage-linux" -ForegroundColor Cyan
    Write-Host "  unzip sqlpackage-linux -d ~/sqlpackage" -ForegroundColor Cyan
    Write-Host "  chmod +x ~/sqlpackage/sqlpackage" -ForegroundColor Cyan
    Write-Host ""
}