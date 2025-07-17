# The Azure PowerShell Az module is required.
# See https://learn.microsoft.com/en-us/powershell/azure/install-azure-powershell?view=azps-10.3.0 for installation instructions
# Add a flag to determine whether to pull ACRE clusters
param(
    [switch]$PullAcre
)

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

    $replicasPerMasterTable = @{
        "Basic"    = 0
        "Standard" = 1
        "Premium"  = 1  # Set a default value if cluster.replicas_per_master is null or missing
    }

    $skuCapacity = ""
    $resourceGroupName = ""
    $cache = $null
    $apiVersion = "2023-05-01-preview"
    
    if ($ResourceId -eq "" -or $null -eq $ResourceId) {
        Write-Host "ResourceId can't be null in Get-Extended-Information function"
    } else {
        # Get the extended properties of the instance
        $cache = Get-AzResource -ResourceId $ResourceId -ExpandProperties -ApiVersion $apiVersion

        if ($null -ne $cache -and $null -ne $cache.Properties -and $null -ne $cache.Properties.replicasPerMaster) {
            $replicasPerMaster = $cache.Properties.replicasPerMaster
        } else {
            # Add null check for $cache.Properties.sku.name before accessing $replicasPerMasterTable
            if ($null -ne $cache -and $null -ne $cache.Properties -and $null -ne $cache.Properties.sku.name) {
                $replicasPerMaster = $replicasPerMasterTable[$cache.Properties.sku.name]
            } else {
                $replicasPerMaster = 1 # Default value if sku.name is null or missing
            }
        } 

        $skuCapacity = $cache.Properties.sku.family + $cache.Properties.sku.capacity
        $resourceGroupName = $cache.ResourceGroupName     
    }
 
    return [PSCustomObject]@{
        ReplicasPerMaster = $replicasPerMaster
        SkuCapacity = $skuCapacity
        ResourceGroupName = $resourceGroupName
    }
}

# Define a dictionary to map SKU names and capacities to master shards and vCPUs
$acreClusterInfo = @{
    "Enterprise_E1" = @{ "vCPUs" = 1; "MasterShards" = 1 }
    "Enterprise_E5" = @{ "vCPUs" = 2; "MasterShards" = 1 }
    "Enterprise_E10" = @{ "vCPUs" = 4; "MasterShards" = 2 }
    "Enterprise_E20" = @{ "vCPUs" = 8; "MasterShards" = 6 }
    "Enterprise_E50" = @{ "vCPUs" = 16; "MasterShards" = 6 }
    "Enterprise_E100" = @{ "vCPUs" = 32; "MasterShards" = 30 }
    "Enterprise_E200" = @{ "vCPUs" = 64; "MasterShards" = 30 }
    "Enterprise_E400" = @{ "vCPUs" = 128; "MasterShards" = 60 }
}

# Function to lookup enterprise SKU capacity
function Lookup-Enterprise-SKU-Capacity {
    param (
        [string]$SkuName,
        [int]$Capacity
    )

    if ($acreClusterInfo.ContainsKey($SkuName)) {
        return $acreClusterInfo[$SkuName]
    } else {
        Write-Host "Invalid SKU name or capacity: $SkuName"
        return $null
    }
}

# Modify the metrics collection logic for enterprise clusters
function Get-Enterprise-Cluster-Metrics {
    param (
        [string]$ResourceId
    )

    $opsPerSecond = (Get-Max-Metric $ResourceId "operationspersecond").ToString("N0")
    $usedMemory = ((Get-Max-Metric $ResourceId "usedmemory") / 1024 / 1024).ToString("F2") # Convert bytes to megabytes
    $connectedClients = Get-Max-Metric $ResourceId "connectedclients"

    return [PSCustomObject]@{
        AvgOpsPerSec = $opsPerSecond
        UsedMemoryMB = $usedMemory
        MaxTotalConnections = $connectedClients
    }
}

# Authenticate to your Azure account (you might need to log in)
Connect-AzAccount 

# Get a list of all Azure subscriptions
Write-Host "Gathering subscription information..."
$subscriptions = Get-AzSubscription
$redisInstances = @()

# Build an array containing all Azure Cache for Redis instances in all subscriptions
foreach ($subscription in $subscriptions) {
    Set-AzContext -Subscription $subscription

    Write-Host "Gathering cluster information for subscription $($subscription.Id)"

    # Get all Azure Cache for Redis instances in the current subscription
    $subscriptionRedisInstances = Get-AzRedisCache

    # Get all Azure Cache for Redis Enterprise instances if PullAcre flag is set
    $subscriptionRedisEnterpriseInstances = @()
    if ($PullAcre) {
        $subscriptionRedisEnterpriseInstances = Get-AzResource -ResourceType "Microsoft.Cache/redisEnterprise" -ExpandProperties
    }

    # Check if SubscriptionID exists before adding it
    $subscriptionRedisInstances | ForEach-Object {
        if (-not $_.PSObject.Properties.Match("SubscriptionID")) {
            $_ | Add-Member -MemberType NoteProperty -Name "SubscriptionID" -Value $subscription.SubscriptionId | Out-Null
        }
    }

    $subscriptionRedisEnterpriseInstances | ForEach-Object {
        if (-not $_.PSObject.Properties.Match("SubscriptionID")) {
            $_ | Add-Member -MemberType NoteProperty -Name "SubscriptionID" -Value $subscription.SubscriptionId | Out-Null
        }
    }

    if ($null -eq $subscriptionRedisInstances.Id -and $null -eq $subscriptionRedisEnterpriseInstances.Id) {
        Write-Host "No Redis Instances found in subscription: $($subscription.Id)"
    } else {
        $redisInstances += ($subscriptionRedisInstances + $subscriptionRedisEnterpriseInstances)
    }
}

$clusterRows = New-Object System.Collections.ArrayList

# Gather statistics for each instance
foreach ($instance in $redisInstances) {

    Write-Host "." -NoNewline
    
    # API returns null if shard count is 1, so set to 1
    if ($null -eq $instance.ShardCount) { 
        $shardCount = 1
    } else { 
        $shardCount = $instance.ShardCount 
    }
    $extendedInfo = Get-Extended-Information $instance.Id

    if ($instance.ResourceType -eq "Microsoft.Cache/redisEnterprise") {
        # Exclude AMR clusters from processing
        $amrClusterInfo = @{
            "SKU" = @(
                "GeneralPurpose_G3", "GeneralPurpose_G5", "Balanced_B0", "Balanced_B1", "Balanced_B3", "Balanced_B5", "Balanced_B10", "Balanced_B20", "Balanced_B50", "Balanced_B100", "Balanced_B150", "Balanced_B250", "Balanced_B350", "Balanced_B500", "Balanced_B700", "Balanced_B100", 
                "MemoryOptimized_M10", "MemoryOptimized_M20", "MemoryOptimized_M50", "MemoryOptimized_M100", "MemoryOptimized_M150", "MemoryOptimized_M250", "MemoryOptimized_M350", "MemoryOptimized_M500", "MemoryOptimized_M700", "MemoryOptimized_M1000", "MemoryOptimized_M1500", "MemoryOptimized_M2000", 
                "ComputeOptimized_X3", "ComputeOptimized_X5", "ComputeOptimized_X10", "ComputeOptimized_X20", "ComputeOptimized_X50", "ComputeOptimized_X100", "ComputeOptimized_X150", "ComputeOptimized_X250", "ComputeOptimized_X350", "ComputeOptimized_X500", "ComputeOptimized_X700", 
                "FlashOptimized_A250", "FlashOptimized_A500", "FlashOptimized_A700", "FlashOptimized_A1000", "FlashOptimized_A1500", "FlashOptimized_A2000", "FlashOptimized_A4500"
            )
        }

        if ($instance.Sku.Name -notin $amrClusterInfo.SKU) {
            $skuInfo = Lookup-Enterprise-SKU-Capacity $instance.Sku.Name $instance.Sku.Capacity

            if ($null -ne $skuInfo) {
                $metrics = Get-Enterprise-Cluster-Metrics $instance.Id

                $skuCapacityFormatted = "$($instance.Sku.Name.Split('_')[-1])-Capacity$($instance.Sku.Capacity)"

                # Update SKU Name to only include 'Enterprise' without the suffix
                $skuNameFormatted = $instance.Sku.Name.Split('_')[0]

                $clusterRow = [ordered]@{
                    "Subscription ID" = $instance.SubscriptionID
                    "Resource Group" = $instance.ResourceGroupName
                    "Region" = $instance.Location
                    "DB Name" = $instance.Name
                    "SKU Capacity" = $skuCapacityFormatted
                    "SKU Name" = $skuNameFormatted
                    "Replicas Per Master" = $skuInfo.MasterShards
                    "Shard Count" = $skuInfo.MasterShards
                    "Shard Number" = 0
                    "Avg Ops/Sec" = $metrics.AvgOpsPerSec
                    "Used Memory (MB)" = $metrics.UsedMemoryMB
                    "Max Total Connections" = $metrics.MaxTotalConnections
                }

                $clusterRows.Add([PSCustomObject]$clusterRow) | Out-Null
            }
        }
    } else {
        # For each shard, gather statistics and add to array
        0..($shardCount - 1) | ForEach-Object {        
            $opsPerSecond = (Get-Max-Metric $instance.Id "operationspersecond$($_)").ToString("N0")
            $usedMemory = ((Get-Max-Metric $instance.Id "usedmemory$($_)") / 1024 / 1024).ToString("F2") # Convert bytes to megabytes
            $connectedClients = Get-Max-Metric $instance.Id "connectedclients$($_)"

            $clusterRow = [ordered]@{ 
                "Subscription ID" = $instance.SubscriptionID; 
                "Resource Group" = $extendedInfo.ResourceGroupName;
                "Region" = $instance.Location;
                "DB Name" = $instance.Name;
                "SKU Capacity" = $extendedInfo.SkuCapacity;
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
}

# Disconnect from your Azure account
Disconnect-AzAccount | Out-Null

# Write to CSV
$clusterRows | Export-Csv $OUTPUT_FILE_NAME -NoTypeInformation

Write-Host "`nResults are in $($OUTPUT_FILE_NAME)"