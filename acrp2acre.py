import datetime
from azure.identity import AzureCliCredential
from azure.mgmt.monitor import MonitorManagementClient
from azure.mgmt.redis import RedisManagementClient
from azure.mgmt.redis.models import SkuName

# Authenticate using Azure CLI credentials
credential = AzureCliCredential()

#TODO: Pass in via command line
# Replace with your subscription ID
subscription_id = 'ef03f41d-d2bd-4691-b3a0-3aff1c6711f7'

# Create clients for Monitor and Redis
monitor_client = MonitorManagementClient(credential, subscription_id)
redis_client = RedisManagementClient(credential, subscription_id)

# Get all Redis instances in the subscription
redis_instances = redis_client.redis.list_by_subscription()

# Filter Redis instances by Premium SKU
# Using BASIC right now for testing. Make it configurable?
premium_redis_instances = [instance for instance in redis_instances if instance.sku.name == SkuName.BASIC.value]

# List of Redis Monitor metrics to retrieve
metrics_to_retrieve = [
    # "cachehits",
    # "cachemisses",
    "cacheRead",
    # "cacheWrite",
    # "connectedclients",
    # "evictedkeys",
    # "expiredkeys",
    # "getcommands",
    # "setcommands",
    # "totalcommandsprocessed",
    # "totalkeys",
    # "usedmemory",
    # "usedmemoryRss",
    # "serverLoad"
]

# Function to get Redis Monitor metrics
def get_redis_monitor_metrics(resource_id, metric_names, start_time, end_time):
    metric_data = monitor_client.metrics.list(
        resource_id,
        metricnames=','.join(metric_names),
        timespan=f"{start_time}/{end_time}",
        #TODO: What interval is appropriate for each metric?
        interval='P1D',
        aggregation='Maximum'
    )

    metrics = {}
    for metric in metric_data.value:
        #TODO: Need to get max instead of last, probably
        #print(metric)
        metric_name = metric.name.value
        print(metric_name)
        if metric.timeseries:            
            print(f'TimeSeries: {metric.timeseries}')
            data_points = metric.timeseries[0].data
            for point in data_points:
                print(point.maximum)
            if data_points:
                last_data_point = data_points[-1]
                metrics[metric_name] = {
                    #"total": last_data_point.total,
                    #"average": last_data_point.average,
                    #"minimum": last_data_point.minimum,
                    "maximum": last_data_point.maximum,
                    #"count": last_data_point.count
                }
    return metrics

# Time range for metrics
end_time = datetime.datetime.utcnow()
start_time = end_time - datetime.timedelta(days=7)

# Fetch and print metrics for each Premium Redis instance
for instance in premium_redis_instances:
    print(f"Redis Instance: {instance.name}")
    print(f"Resource ID: {instance.id}, HostName: {instance.host_name}, Location: {instance.location}")

    metrics = get_redis_monitor_metrics(instance.id, metrics_to_retrieve, start_time, end_time)
    for metric_name, metric_values in metrics.items():
        print(f"{metric_name}: {metric_values}")

    print("\n")