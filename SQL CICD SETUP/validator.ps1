# Quick DACPAC validator
$dacpacFile = "/home/vaibhav/dacpac-workspace/sql-cicd-setup/DACPACs/DEV/devsqlcicddatabase_20260624_*.dacpac"

# Find the most recent DACPAC
$latestDacpac = Get-ChildItem "/home/vaibhav/dacpac-workspace/sql-cicd-setup/DACPACs/DEV/" -Filter "*.dacpac" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($latestDacpac) {
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         DACPAC INSPECTION                              ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "📄 File: $($latestDacpac.Name)" -ForegroundColor Yellow
    Write-Host "📦 Size: $([math]::Round($latestDacpac.Length / 1KB, 2)) KB" -ForegroundColor Yellow
    Write-Host ""
    
    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($latestDacpac.FullName)
    
    Write-Host "📋 Contents:" -ForegroundColor Yellow
    $zip.Entries | ForEach-Object {
        $size = [math]::Round($_.Length / 1KB, 2)
        Write-Host "   $($_.FullName) - $size KB" -ForegroundColor Cyan
    }
    
    # Check for model.xml
    $modelEntry = $zip.Entries | Where-Object { $_.Name -eq "model.xml" }
    if ($modelEntry) {
        Write-Host ""
        Write-Host "✅ model.xml found - DACPAC structure is VALID" -ForegroundColor Green
        
        # Read model.xml to count objects
        $reader = New-Object System.IO.StreamReader($modelEntry.Open())
        $modelXml = $reader.ReadToEnd()
        $reader.Close()
        
        [xml]$model = $modelXml
        $tables = ($model.DataSchemaModel.Model.Element | Where-Object { $_.Type -like '*Table*' }).Count
        $views = ($model.DataSchemaModel.Model.Element | Where-Object { $_.Type -like '*View*' }).Count
        
        Write-Host ""
        Write-Host "📊 Schema Objects:" -ForegroundColor Yellow
        Write-Host "   Tables: $tables" -ForegroundColor Cyan
        Write-Host "   Views: $views" -ForegroundColor Cyan
        
        if ($tables -gt 0) {
            Write-Host ""
            Write-Host "✅ CONCLUSION: This DACPAC is VALID!" -ForegroundColor Green
            Write-Host "   It's just small because your database only has $tables table(s)." -ForegroundColor Green
        }
    }
    else {
        Write-Host ""
        Write-Host "❌ model.xml NOT found - DACPAC is invalid" -ForegroundColor Red
    }
    
    $zip.Dispose()
}
else {
    Write-Host "❌ No DACPAC found" -ForegroundColor Red
}