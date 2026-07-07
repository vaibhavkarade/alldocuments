# Variables
$ResourceGroup = "rg-trinity-dev-data-core-northeurope"
$StorageAccountName = "satrinitydevdatacorest02"

# Output file paths (Cloud Shell saves to /home/<username>/clouddrive)
$containerReportFile = "satrinitydevdatacorest02_container_report.csv"
$blobReportFile      = "satrinitydevdatacorest02_blob_report.csv"

# Get the storage account context
$ctx = (Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccountName).Context

# Get all containers
$containers = Get-AzStorageContainer -Context $ctx

# Initialize arrays for reports
$containerReport = @()
$blobReport = @()

foreach ($container in $containers) {
    Write-Host "Processing container: $($container.Name)..."

    # Get all blobs in the container
    $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx

    # Container summary
    $totalSizeBytes = ($blobs | Measure-Object -Property Length -Sum).Sum
    $totalSizeGB = [Math]::Round($totalSizeBytes / 1GB, 2)

    $containerReport += [PSCustomObject]@{
        ContainerName = $container.Name
        TotalBlobs    = $blobs.Count
        TotalSizeGB   = $totalSizeGB
    }

    # Blob details
    foreach ($blob in $blobs) {
        $blobReport += [PSCustomObject]@{
            ContainerName = $container.Name
            BlobName      = $blob.Name
            BlobSizeMB    = [Math]::Round($blob.Length / 1MB, 2)
            LastModified  = $blob.LastModified
        }
    }
}

# Export to CSV
$containerReport | Export-Csv -Path $containerReportFile -NoTypeInformation
$blobReport      | Export-Csv -Path $blobReportFile -NoTypeInformation

Write-Host "`nReports generated successfully:"
Write-Host "Container summary report: $containerReportFile"
Write-Host "Blob details report: $blobReportFile"