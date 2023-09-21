# The Azure PowerShell Az module is required.
# See https://learn.microsoft.com/en-us/powershell/azure/install-azure-powershell?view=azps-10.3.0 for installation instructions

# Static config
$METRIC_COLLECTION_PERIOD_DAYS = 7 # Look at last seven days of metrics when calculating statistics
$METRIC_AGGREGATION_PERIOD = "01:00:00" # When aggregating metrics, use a one hour time window
$OUTPUT_FILE_NAME = "AzureStats.csv" #TODO: Allow output path/filename to be passed in from command-line

# Get the maximum average over the collection period
function Get-Max-Average-Metric ($ResourceId, $MetricName) {

    $start_date = (Get-Date).Date.AddDays(1).AddDays(-$METRIC_COLLECTION_PERIOD_DAYS)
    $metrics = (
        Get-AzMetric -TimeGrain $METRIC_AGGREGATION_PERIOD -ResourceId $ResourceId -MetricName $MetricName -StartTime $start_date `
         -AggregationType Average -WarningAction:SilentlyContinue
    ).Timeseries

    $averages = @()

    $metrics | ForEach-Object {
        $averages += $_.Data.Average
    }
    return ($averages | Measure-Object -Maximum).Maximum
}

# Get the absolute maximum over the collection period
function Get-Max-Metric ($ResourceId, $MetricName) {

    $start_date = (Get-Date).Date.AddDays(1).AddDays(-$METRIC_COLLECTION_PERIOD_DAYS)
    $metrics = (
        Get-AzMetric -TimeGrain $METRIC_AGGREGATION_PERIOD -ResourceId $ResourceId -MetricName $MetricName -StartTime $start_date `
         -AggregationType Maximum -WarningAction:SilentlyContinue
    ).Timeseries

    $maximums = @()

    $metrics | ForEach-Object {
        $maximums += $_.Data.Maximum
    }

    return ($maximums | Measure-Object -Maximum).Maximum
}

function Get-Extended-Information($ResourceId) {

    $replicasPerMaster = 0
    $skuName = ""
    $resourceGroupName = ""
    
    if ($ResourceId -eq "" -or $null -eq $ResourceId) {
        Write-Host "ResourceId can't be null in Get-Extended-Information function"
    } else {
        # Get the extended properties of the instance
        $cache = Get-AzResource -ResourceId $ResourceId -ExpandProperties

        if ($null -ne $cache -and $null -ne $cache.Properties -and $null -ne $cache.Properties.replicasPerMaster) {
            $replicasPerMaster = $cache.Properties.replicasPerMaster
        } 

        $skuName = $cache.Properties.sku.family + $cache.Properties.sku.capacity
        $resourceGroupName = $cache.ResourceGroupName     
    }
 
    return [PSCustomObject]@{
        ReplicasPerMaster = $replicasPerMaster
        SkuName = $skuName
        ResourceGroupName = $resourceGroupName
    }
}

# Authenticate to your Azure account (you might need to log in)
Connect-AzAccount 

# Get a list of all Azure subscriptions
Write-Host "Gathering subscription information..."
$subscriptions = Get-AzSubscription
$redisInstances = New-Object System.Collections.ArrayList

# Build an array containing all Azure Cache for Redis instances in all subscriptions
foreach ($subscription in $subscriptions) {
    Set-AzContext -Subscription $subscription

    Write-Host "Gathering cluster information for subscription $($subscription.Id)"

    # Get all Azure Cache for Redis instances in the current subscription
    $subscriptionRedisInstances = Get-AzRedisCache

    # Attach the subscription ID to each redis instance object, so we can include it in the output
    $subscriptionRedisInstances | ForEach-Object {
        $_ | Add-Member -MemberType NoteProperty -Name "SubscriptionID" -Value $subscription.SubscriptionId | Out-Null
    }    
    
    $redisInstances.AddRange($subscriptionRedisInstances)
}

$clusterRows = New-Object System.Collections.ArrayList

# Gather statistics for each instance
foreach ($instance in $redisInstances) {

    Write-Host "." -NoNewline
    
    # API returns null if shard count is 1, so set to 1
    If ($null -eq $instance.ShardCount) { 
        $shardCount = 1
    } else { 
        $shardCount = $instance.ShardCount 
    }
    
    # For each shard, gather statistics and add to array
    0..($shardCount - 1) | ForEach-Object {        
        $opsPerSecond = (Get-Max-Average-Metric $instance.Id "operationspersecond$($_)").ToString("N0")
        $usedMemory = ((Get-Max-Metric $instance.Id "usedmemory$($_)") / 1024 / 1024).ToString("F2") # Convert bytes to megabytes
        $connectedClients = Get-Max-Metric $instance.Id "connectedclients$($_)"

        # TODO: Find a way to get "Replicas Per Master" from Powershell. This is useful information that the Python version collects.
        $extendedInfo = Get-Extended-Information $instance.Id
        # TODO: Find a way to get the full instance type (e.g. P5). This is useful information that the Python version collects.
        
        $clusterRow = [ordered]@{ 
            "Subscription ID" = $instance.SubscriptionID; 
            "Resource Group" = $extendedInfo.ResourceGroupName;
            "DB Name" = $instance.Name;
            "SKU Size" = $instance.Size;
            "SKU Capacity" = $extendedInfo.SkuName;
            "SKU Name" = $instance.Sku;
            "Replicas Per Master" = $extendedInfo.ReplicasPerMaster;
            "Shard Count" = $shardCount;
            "Shard Number" = $_;
            "Avg Ops/Sec" = $opsPerSecond;
            "Used Memory (MB)" = $usedMemory;
            "Max Total Connections" = $connectedClients;
        }
        
        $clusterRows.Add([PSCustomObject]$clusterRow) | Out-Null # Cast to PSCustomObject is required for compatibility with Windows PowerShell 5.1
    }
}

# Disconnect from your Azure account
Disconnect-AzAccount | Out-Null

# Write to CSV
$clusterRows | Export-Csv $OUTPUT_FILE_NAME -NoTypeInformation

Write-Host "`nResults are in $($OUTPUT_FILE_NAME)"