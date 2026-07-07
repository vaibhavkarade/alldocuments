# ------------------ CONFIGURATION ------------------
Write-Output "Starting Azure Idle Resources Deployment Script"

# Configurable variables
$subscriptionId = "8172f712-63ee-44d9-8b59-3fa257b9dcbd"  # Replace with your subscription ID
$location = "eastus"                                      # Specify deployment location
$sqlLocation = "centralus"                                # Secondary location for SQL Server if restrictions exist
$resourceGroup = "rg-cost-optimization-test"              # Resource group name
$uniqueSuffix = (Get-Date -Format "yyyyMMddHHmmss")       # Unique timestamp suffix for resource names

# Resource Names
$vmName = "testIdleVM"
$storageAccountName = "idlestorage$uniqueSuffix"
$appServicePlan = "testAppServicePlan"
$webAppName = "idlewebapp$uniqueSuffix"
$sqlServerName = "sqlidle$uniqueSuffix"
$sqlDbName = "idledb"
$keyVaultName = "kv-idle-$uniqueSuffix"
$recoveryVaultName = "idle-recovery-vault-$uniqueSuffix"
$lbName = "idleLB-$uniqueSuffix"
$appGwName = "idleAppGateway-$uniqueSuffix"

# Tag for all resources
$tags = @{Purpose="IdleTest"; Environment="Development"}

# ------------------ RESOURCE GROUP CLEANUP ------------------
Write-Output "Checking if resource group '$resourceGroup' exists and cleaning up if needed..."
if ((Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue) -ne $null) {
    Remove-AzResourceGroup -Name $resourceGroup -Force -AsJob
    Get-Job | Wait-Job | Out-Null
    Write-Output "✅ Resource group '$resourceGroup' deleted successfully!"
} else {
    Write-Output "Resource group '$resourceGroup' does not exist. Proceeding with deployment."
}

# ------------------ SET SUBSCRIPTION CONTEXT ------------------
Write-Output "Setting subscription context..."
Set-AzContext -SubscriptionId $subscriptionId

# ------------------ RESOURCE GROUP CREATION ------------------
Write-Output "Creating resource group '$resourceGroup'..."
New-AzResourceGroup -Name $resourceGroup -Location $location -Tag $tags
Write-Output "✅ Resource group '$resourceGroup' created successfully."

# ------------------ CREATE IDLE VIRTUAL MACHINE ------------------
try {
    Write-Output "Creating idle Virtual Machine..."
    # Create Virtual Network (VNet) and Subnet
    $vnet = New-AzVirtualNetwork -Name "$vmName-vnet-$uniqueSuffix" `
        -ResourceGroupName $resourceGroup -Location $location `
        -AddressPrefix "10.0.0.0/16" `
        -Subnet @(New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.0.1.0/24")

    # Create Network Interface Card (NIC)
    $nic = New-AzNetworkInterface -Name "$vmName-nic-$uniqueSuffix" `
        -ResourceGroupName $resourceGroup -Location $location `
        -SubnetId $vnet.Subnets[0].Id

    # VM Login Credentials
    $cred = Get-Credential -Message "Enter credentials for the Virtual Machine"

    # Configure VM
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B1s" `
        | Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate `
        | Add-AzVMNetworkInterface -Id $nic.Id `
        | Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" `
          -Offer "WindowsServer" -Skus "2019-Datacenter" -Version "latest"

    # Create and Stop VM
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig
    Stop-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Force
    Write-Output "✅ Idle Virtual Machine '$vmName' created and stopped."
} catch {
    Write-Output "❌ Failed to create Virtual Machine: $_"
}

# ------------------ CREATE UNATTACHED MANAGED DISK ------------------
try {
    Write-Output "Creating unattached managed disk..."
    New-AzDisk -ResourceGroupName $resourceGroup -DiskName "unattachedDisk-$uniqueSuffix" `
        -DiskSku Standard_LRS -DiskSizeGB 10 -CreationData @{CreateOption = "Empty"} -Tag $tags
    Write-Output "✅ Unattached managed disk created."
} catch {
    Write-Output "❌ Failed to create unattached managed disk: $_"
}

# ------------------ CREATE UNASSOCIATED PUBLIC IP ------------------
try {
    Write-Output "Creating unassociated public IP..."
    New-AzPublicIpAddress -Name "unassociatedPIP-$uniqueSuffix" -ResourceGroupName $resourceGroup `
        -Location $location -AllocationMethod Static -Tag $tags
    Write-Output "✅ Unassociated public IP created."
} catch {
    Write-Output "❌ Failed to create Public IP: $_"
}

# ------------------ CREATE STOPPED APP SERVICE ------------------
try {
    Write-Output "Creating idle App Service..."
    New-AzAppServicePlan -Name $appServicePlan -Location $location -ResourceGroupName $resourceGroup `
        -Tier "Free" -NumberofWorkers 1 -Tag $tags
    New-AzWebApp -Name $webAppName -Location $location -AppServicePlan $appServicePlan `
        -ResourceGroupName $resourceGroup -Tag $tags
    Stop-AzWebApp -ResourceGroupName $resourceGroup -Name $webAppName
    Write-Output "✅ Idle App Service created and stopped."
} catch {
    Write-Output "❌ Failed to create App Service: $_"
}

# ------------------ CREATE LOW-USAGE STORAGE ACCOUNT ------------------
try {
    Write-Output "Creating low-usage Storage Account..."
    New-AzStorageAccount -ResourceGroupName $resourceGroup `
        -Name $storageAccountName -Location $location `
        -SkuName "Standard_LRS" -Kind "StorageV2" -Tag $tags
    Write-Output "✅ Storage account '$storageAccountName' successfully created."
} catch {
    Write-Output "❌ Failed to create storage account: $_"
}

# ------------------ CREATE SQL SERVER AND DATABASE ------------------
try {
    Write-Output "Creating idle SQL Server and Database..."
    $sqlCred = Get-Credential -Message "Enter SQL admin credentials (Ensure strong password)"
    New-AzSqlServer -ResourceGroupName $resourceGroup -ServerName $sqlServerName `
        -Location $sqlLocation -SqlAdministratorCredentials $sqlCred -Tag $tags
    New-AzSqlDatabase -ResourceGroupName $resourceGroup -ServerName $sqlServerName `
        -DatabaseName $sqlDbName -Edition "Basic" -Tag $tags
    Write-Output "✅ SQL Server and idle Database created."
} catch {
    Write-Output "❌ Failed to create SQL Server or Database: $_"
}

# ------------------ CREATE KEY VAULT ------------------
try {
    Write-Output "Creating Key Vault..."
    New-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroup `
        -Location $location -EnabledForDeployment -Tag $tags
    Write-Output "✅ Key Vault '$keyVaultName' successfully created."
} catch {
    Write-Output "❌ Failed to create Key Vault: $_"
}

# ------------------ CREATE RECOVERY SERVICES VAULT ------------------
try {
    Write-Output "Creating Recovery Services Vault..."
    New-AzRecoveryServicesVault -Name $recoveryVaultName -ResourceGroupName $resourceGroup `
        -Location $location -Tag $tags
    Write-Output "✅ Recovery Services Vault created successfully."
} catch {
    Write-Output "❌ Failed to create Recovery Services Vault: $_"
}

# ------------------ CREATE LOAD BALANCER ------------------
try {
    Write-Output "Creating Load Balancer..."
    $publicIp = New-AzPublicIpAddress -ResourceGroupName $resourceGroup `
        -Location $location -AllocationMethod Static -Name "lbPublicIp-$uniqueSuffix" -Tag $tags
    $frontendIP = New-AzLoadBalancerFrontendIpConfig -Name "frontendConfig" -PublicIpAddress $publicIp
    New-AzLoadBalancer -ResourceGroupName $resourceGroup -Name $lbName `
        -Location $location -FrontendIpConfiguration $frontendIP -Tag $tags
    Write-Output "✅ Load Balancer created successfully."
} catch {
    Write-Output "❌ Failed to create Load Balancer: $_"
}

# ------------------ COMPLETION ------------------
Write-Output "✅ All resources successfully created in resource group '$resourceGroup'."
Write-Output "💡 Remember to clean up with 'Remove-AzResourceGroup -Name $resourceGroup -Force' once testing is complete."