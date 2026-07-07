# Azure Cost Optimization Scanner Script - All Resources Included

# Authenticate using Managed Identity
Write-Output "Connecting to Azure..."
Connect-AzAccount -Identity
$subscriptionId = "<your-subscription-id>"
Select-AzSubscription -SubscriptionId $subscriptionId

Write-Output "Fetching all resources..."
$optimizationSuggestions = @()

# 1. Underutilized Virtual Machines
$vms = Get-AzVM
foreach ($vm in $vms) {
    $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
    if ($vmStatus.Statuses[1].Code -eq "PowerState/running") {
        $metric = Get-AzMetric -ResourceId $vm.Id -MetricName "Percentage CPU" -TimeGrain "PT1H" -TimeSpan (Get-Date).AddDays(-7)
        $avgCPU = ($metric.Data | Measure-Object Average -Average).Average
        if ($avgCPU -lt 10) {
            $optimizationSuggestions += [PSCustomObject]@{
                ResourceName = $vm.Name
                ResourceType = "VirtualMachine"
                Suggestion = "Low CPU usage (<10%) – consider resizing or shutting down"
            }
        }
    }
}

# 2. Unattached Disks
$disks = Get-AzDisk
foreach ($disk in $disks) {
    if (-not $disk.ManagedBy) {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $disk.Name
            ResourceType = "ManagedDisk"
            Suggestion = "Unattached disk – consider deleting"
        }
    }
}

# 3. Unassociated Public IPs
$pips = Get-AzPublicIpAddress
foreach ($pip in $pips) {
    if (-not $pip.IpConfiguration) {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $pip.Name
            ResourceType = "PublicIP"
            Suggestion = "Unassociated Public IP – consider deleting"
        }
    }
}

# 4. Unused NICs
$nics = Get-AzNetworkInterface
foreach ($nic in $nics) {
    if (-not $nic.VirtualMachine) {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $nic.Name
            ResourceType = "NetworkInterface"
            Suggestion = "Unused NIC – consider deleting"
        }
    }
}

# 5. App Services (Stopped)
$appServices = Get-AzWebApp
foreach ($app in $appServices) {
    if ($app.State -ne "Running") {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $app.Name
            ResourceType = "AppService"
            Suggestion = "Stopped – consider removing or downgrading"
        }
    }
}

# 6. Storage Accounts – find low storage usage (<1 GB total blob size)
$storageAccounts = Get-AzStorageAccount
foreach ($sa in $storageAccounts) {
    $ctx = $sa.Context
    $totalSizeBytes = 0

    try {
        $containers = Get-AzStorageContainer -Context $ctx
        foreach ($container in $containers) {
            $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx
            foreach ($blob in $blobs) {
                $totalSizeBytes += $blob.ICloudBlob.Properties.Length
            }
        }
    } catch {
        Write-Warning "Failed to access container/blob info for storage account: $($sa.StorageAccountName)"
        continue
    }

    $totalSizeGB = [math]::Round($totalSizeBytes / 1GB, 2)

    if ($totalSizeGB -lt 1) {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $sa.StorageAccountName
            ResourceType = "StorageAccount"
            Suggestion = "Low usage ($totalSizeGB GB) – consider deleting unused containers or switching to Cool/Archive tier"
        }
    }
}

# 7. Azure SQL Databases (Low DTU/CPU usage)
$sqlDatabases = Get-AzSqlDatabase
foreach ($sqlDb in $sqlDatabases) {
    if ($sqlDb.Edition -ne "Hyperscale") {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $sqlDb.Name
            ResourceType = "SQLDatabase"
            Suggestion = "Check performance usage – consider scaling down or auto-pause (if serverless)"
        }
    }
}

# 8. Azure Load Balancers (No backend pool)
$loadBalancers = Get-AzLoadBalancer
foreach ($lb in $loadBalancers) {
    if ($lb.FrontendIpConfigurations.Count -gt 0 -and $lb.BackendAddressPools.Count -eq 0) {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $lb.Name
            ResourceType = "LoadBalancer"
            Suggestion = "No backend pool – consider decommissioning"
        }
    }
}

# 9. Application Gateways (No listeners)
$appGateways = Get-AzApplicationGateway
foreach ($gw in $appGateways) {
    if ($gw.HttpListeners.Count -eq 0) {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $gw.Name
            ResourceType = "ApplicationGateway"
            Suggestion = "No listeners – consider deleting"
        }
    }
}

# 10. Key Vaults (No secrets/certs/keys)
$keyVaults = Get-AzKeyVault
foreach ($kv in $keyVaults) {
    $secrets = Get-AzKeyVaultSecret -VaultName $kv.VaultName -ErrorAction SilentlyContinue
    if ($secrets.Count -eq 0) {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $kv.VaultName
            ResourceType = "KeyVault"
            Suggestion = "Empty Key Vault – consider removing if not in use"
        }
    }
}

# 11. Recovery Services Vaults (no backup items)
$recoveryVaults = Get-AzRecoveryServicesVault
foreach ($vault in $recoveryVaults) {
    Set-AzRecoveryServicesVaultContext -Vault $vault
    $backupItems = Get-AzRecoveryServicesBackupItem -VaultId $vault.ID -ErrorAction SilentlyContinue
    if ($backupItems.Count -eq 0) {
        $optimizationSuggestions += [PSCustomObject]@{
            ResourceName = $vault.Name
            ResourceType = "RecoveryServicesVault"
            Suggestion = "No backup items – consider deleting"
        }
    }
}

# ===== Output & Export =====
Write-Output "`n===== Cost Optimization Suggestions ====="
$optimizationSuggestions | Format-Table -AutoSize

# Export to CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$reportPath = "C:\Temp\AzureCostOptimizationReport_$timestamp.csv"
$optimizationSuggestions | Export-Csv -Path $reportPath -NoTypeInformation
Write-Output "Report exported to $reportPath"
