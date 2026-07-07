# Define Storage Account Details
$StorageAccountName = "satrinitydevdatacorest02"
$ResourceGroupName = "rg-trinity-dev-data-core-northeurope"
$ReportFile = "ContainerReportLarge.csv"

# Utility function to format bytes to human-readable sizes
function Format-Size {
    param ($Bytes)
    switch ($Bytes) {
        {$_ -ge 1PB} {"{0:N2} PB" -f ($Bytes / 1PB); break}
        {$_ -ge 1TB} {"{0:N2} TB" -f ($Bytes / 1TB); break}
        {$_ -ge 1GB} {"{0:N2} GB" -f ($Bytes / 1GB); break}
        {$_ -ge 1MB} {"{0:N2} MB" -f ($Bytes / 1MB); break}
        {$_ -ge 1KB} {"{0:N2} KB" -f ($Bytes / 1KB); break}
        default {"{0} Bytes" -f $_}
    }
}

Write-Host "Starting data size calculation for Storage Account: $StorageAccountName"

try {
    # Authenticate using Storage Account Key.
    Write-Host "Retrieving storage account key and context..."
    $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $StorageAccountContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    Write-Host "Storage context retrieved successfully!" -ForegroundColor Green
} catch {
    Write-Host "Error: Unable to retrieve storage account context. Exception: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# List all containers in the storage account
try {
    Write-Host "Fetching all containers..."
    $Containers = Get-AzStorageContainer -Context $StorageAccountContext
    if ($Containers.Count -eq 0) {
        Write-Host "No containers found in the storage account: $StorageAccountName" -ForegroundColor Yellow
        exit 0
    }
} catch {
    Write-Host "Error: Unable to list containers. Exception: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize the report file
"Container Name,Data Size (Bytes),Data Size (Readable)" | Out-File -FilePath $ReportFile -Encoding UTF8

# Process each container
foreach ($Container in $Containers) {
    $ContainerName = $Container.Name
    Write-Host "Processing container: $ContainerName..."

    try {
        $TotalSizeBytes = 0
        $ContinuationToken = $null

        do {
            try {
                $BlobBatch = Get-AzStorageBlob -Container $ContainerName -Context $StorageAccountContext -ContinuationToken $ContinuationToken

                if (!$BlobBatch.Results) {
                    Write-Host "No blobs retrieved in this batch. Moving to next..." -ForegroundColor Yellow
                }

                foreach ($Blob in $BlobBatch.Results) {
                    $BlobSize = $Blob.ICloudBlob.Properties.Length
                    $TotalSizeBytes += $BlobSize
                }

                # Extract continuation token
                if ($BlobBatch.ContinuationToken -is [Microsoft.Azure.Storage.Blob.BlobContinuationToken]) {
                    $ContinuationToken = $BlobBatch.ContinuationToken
                    Write-Host "Fetched batch of blobs, continuation token: $($ContinuationToken)" -ForegroundColor Yellow
                } elseif ($BlobBatch.ContinuationToken -is [System.Array] -and $BlobBatch.ContinuationToken.Count -gt 0) {
                    $ContinuationToken = $BlobBatch.ContinuationToken[0]
                    Write-Host "Continuation token retrieved from array." -ForegroundColor Cyan
                } else {
                    Write-Host "No valid continuation token found. Ending batch processing for $ContainerName." -ForegroundColor Green
                    $ContinuationToken = $null
                }
            } catch {
                Write-Host "Error fetching blobs for container: $ContainerName. Exception: $($_.Exception.Message)" -ForegroundColor Red
                $ContinuationToken = $null
            }
        } while ($ContinuationToken -ne $null)

        $ReadableSize = Format-Size -Bytes $TotalSizeBytes
        "$ContainerName,$TotalSizeBytes,$ReadableSize" | Out-File -FilePath $ReportFile -Append -Encoding UTF8
        Write-Host "Completed processing for $ContainerName. Total size: $ReadableSize" -ForegroundColor Green
    } catch {
        Write-Host "Error processing container: $ContainerName. Exception: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
}

Write-Host "Report generation completed!"
Write-Host "Report saved in: $(Resolve-Path $ReportFile)" -ForegroundColor Green