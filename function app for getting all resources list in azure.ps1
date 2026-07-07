param($Request)

# Load modules
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop

try {
    Write-Output "🔐 Connecting to Azure using Managed Identity..."
    Connect-AzAccount -Identity -ErrorAction Stop

    $subscriptionId = "1e5743fb-04ac-4543-a04e-bb91fcad4bf2"
    Write-Output "🔁 Selecting subscription: $subscriptionId"
    Select-AzSubscription -SubscriptionId $subscriptionId -ErrorAction Stop

    Write-Output "📦 Fetching all resources..."
    $resources = Get-AzResource

    if ($resources -and $resources.Count -gt 0) {
        Write-Output "✅ Found $($resources.Count) resources."

        $resourceList = foreach ($resource in $resources) {
            [PSCustomObject]@{
                Name              = $resource.Name
                ResourceType      = $resource.ResourceType
                ResourceGroupName = $resource.ResourceGroupName
                Location          = $resource.Location
                SubscriptionId    = $resource.SubscriptionId
                Id                = $resource.ResourceId
                Tags              = $resource.Tags
            }
        }

        $jsonBody = $resourceList | ConvertTo-Json -Depth 4
    } else {
        Write-Output "⚠️ No resources found or access denied."
        $jsonBody = "No resources found or permission issue."
    }

    Push-OutputBinding -Name Response -Value @{
        StatusCode = 200
        Body       = $jsonBody
    }

} catch {
    Write-Error "❌ ERROR: $_"
    Push-OutputBinding -Name Response -Value @{
        StatusCode = 500
        Body       = "Function failed: $_"
    }
}
