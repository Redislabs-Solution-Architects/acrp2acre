# The Azure PowerShell Az module is required.
# See https://learn.microsoft.com/en-us/powershell/azure/install-azure-powershell?view=azps-10.3.0 for installation instructions


# Authenticate to your Azure account (you might need to log in)
Connect-AzAccount 

# Get a list of all Azure subscriptions
$subscriptions = Get-AzSubscription

# Iterate through each subscription
foreach ($subscription in $subscriptions) {
    Set-AzContext -Subscription $subscription

    # Get all Azure Cache for Redis instances in the current subscription
    $redisInstances = Get-AzRedisCache

    # Display the Redis instances for the current subscription
    Write-Host "Azure Subscription: $($subscription.Name)"
    foreach ($redisInstance in $redisInstances) {
        Write-Host "  Redis Cache Name: $($redisInstance.Name)"
        Write-Host "  Resource Group: $($redisInstance.ResourceGroupName)"
        Write-Host "  Location: $($redisInstance.Location)"
        Write-Host "  SKU: $($redisInstance.Sku)"
        Write-Host "  Memory: $($redisInstance.Size)"
        Write-Host "  Shard Count: $($redisInstance.ShardCount)"
        Write-Host ""
    }
}

# Disconnect from your Azure account
Disconnect-AzAccount | Out-Null
