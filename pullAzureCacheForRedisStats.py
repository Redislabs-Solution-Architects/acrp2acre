from azure.identity import DefaultAzureCredential
from azure.identity import AzureCliCredential
from azure.mgmt.redis import RedisManagementClient
from azure.mgmt.redisenterprise import RedisEnterpriseManagementClient
from azure.mgmt.monitor import MonitorManagementClient
from azure.mgmt.subscription import SubscriptionClient
import datetime
import pandas as pd
from pathlib import Path
import argparse
import os

# The measurement collection period in days.
METRIC_COLLECTION_PERIOD_DAYS = 90

# The aggregation period
# (see https://en.wikipedia.org/wiki/ISO_8601#Durations )
AGGREGATION_PERIOD = "PT1H"

# Seconds in the aggregation period
SECONDS_PER_AGGREGATION_PERIOD = 3600

# Aligned by capacity 2, 4, 6, 8, 10
acreClusterInfo = {
    'SKU' : [ 'Enterprise_E1',
             'Enterprise_E5', 'Enterprise_E5', 'Enterprise_E5', 
             'Enterprise_E10', 'Enterprise_E10', 'Enterprise_E10', 'Enterprise_E10', 'Enterprise_E10',
             'Enterprise_E20', 'Enterprise_E20', 'Enterprise_E20', 'Enterprise_E20', 'Enterprise_E20',
             'Enterprise_E50', 'Enterprise_E50', 'Enterprise_E50', 'Enterprise_E50', 'Enterprise_E50',
             'Enterprise_E100', 'Enterprise_E100', 'Enterprise_E100', 'Enterprise_E100', 'Enterprise_E100',
             'Enterprise_E200', 'Enterprise_E200', 'Enterprise_E200', 'Enterprise_E200', 'Enterprise_E200',
             'Enterprise_E400', 'Enterprise_E400', 'Enterprise_E400', 'Enterprise_E400', 'Enterprise_E400',
             ],
    'vCPUs' : [ 1,
              2, 4, 6,
              4, 8, 12, 16, 20,
              4, 8, 12, 16, 20,
              8, 16, 24, 32, 40,
              16, 32, 48, 64, 80,
              32, 64, 96, 128, 160,
              64, 128, 192, 256, 320],
    'MasterShards': [1,
                     1, 2, 6,
                     2, 6, 6, 30, 30,
                     2, 6, 6, 30, 30,
                     6, 6, 6, 30, 30,
                     6, 30, 30, 30, 30,
                     30, 60, 60, 120, 120,
                     60, 120, 120, 240, 240]
}

amrClusterInfo = {
  'SKU' : [
      'GeneralPurpose_G3', 'GeneralPurpose_G5', 'Balanced_B0', 'Balanced_B1', 'Balanced_B3', 'Balanced_B5', 'Balanced_B10', 'Balanced_B20', 'Balanced_B50', 'Balanced_B100', 'Balanced_B150', 'Balanced_B250', 'Balanced_B350', 'Balanced_B500', 'Balanced_B700', 'Balanced_B100', 
      'MemoryOptimized_M10', 'MemoryOptimized_M20', 'MemoryOptimized_M50', 'MemoryOptimized_M100', 'MemoryOptimized_M150', 'MemoryOptimized_M250', 'MemoryOptimized_M350', 'MemoryOptimized_M500', 'MemoryOptimized_M700', 'MemoryOptimized_M1000', 'MemoryOptimized_M1500', 'MemoryOptimized_M2000', 
      'ComputeOptimized_X3', 'ComputeOptimized_X5', 'ComputeOptimized_X10', 'ComputeOptimized_X20' 'ComputeOptimized_X50', 'ComputeOptimized_X100', 'ComputeOptimized_X150', 'ComputeOptimized_X250', 'ComputeOptimized_X350', 'ComputeOptimized_X500', 'ComputeOptimized_X700', 
      'FlashOptimized_A250', 'FlashOptimized_A500', 'FlashOptimized_A700', 'FlashOptimized_A1000', 'FlashOptimized_A1500', 'FlashOptimized_A2000', 'FlashOptimized_A4500'
  ]
}

clusterInfoDf = pd.DataFrame(acreClusterInfo)

def lookup_enterprise_sku_capcity(sku, capacity):
    # Filter based on SKU
    sku_data = clusterInfoDf[clusterInfoDf['SKU']==sku]
    capacity_index = capacity//2 - 1

    # Check if the capcity is within the range of the filtered DF
    if capacity_index < len(sku_data):
            vcpus = sku_data.iloc[capacity_index]['vCPUs']
            mastershard_count = sku_data.iloc[capacity_index]['MasterShards']
            return {'VCPUs': vcpus, 'MasterShards':  mastershard_count}
    else:
        return 'Invalid capcity index'

def get_max_average_metrics(mc, resource_id, metrics):
    '''
    Return maximum one hour average over the entire timespan
    '''
    today = datetime.date.today() + datetime.timedelta(days=1)
    then = today - datetime.timedelta(days=METRIC_COLLECTION_PERIOD_DAYS)
    timespan = "{}/{}".format(then, today)
    metrics_data = mc.metrics.list(
        resource_id,
        metricnames=metrics,
        timespan=timespan,
        interval=AGGREGATION_PERIOD,
        aggregation="Average")

    # WARNING - if you change the aggregation above then you MUST change the
    # accessor below to its lower case equivalent
    # e.g. if you use "Maximum" above then you'd use metric_value.maximum
    # below.

    # Ugh - this is a very painful expression caused by the nesting of various
    # arrays within the Azure data types.
    result = [
        max(
            [
                metric_value.average
                for ts in metric.timeseries
                for metric_value in ts.data
                if metric_value.average is not None
            ], 
            default = 0
        )
        for metric in metrics_data.value
    ]
    return 0 if len(result) == 0 else result[0]


def get_max_metrics(mc, resource_id, metrics):
    '''
    Return the maximum metric over the entire timespan
    '''
    today = datetime.date.today() + datetime.timedelta(days=1)
    then = today - datetime.timedelta(days=METRIC_COLLECTION_PERIOD_DAYS)
    timespan = "{}/{}".format(then, today)
    metrics_data = mc.metrics.list(
        resource_id,
        metricnames=metrics,
        timespan=timespan,
        interval=AGGREGATION_PERIOD,
        aggregation="Maximum")

    # WARNING - if you change the aggregation above then you MUST change the
    # accessor below to its lower case equivalent
    # e.g. if you use "Maximum" above then you'd use metric_value.maximum
    # below.

    # Ugh - this is a very painful expression caused by the nesting of various
    # arrays within the Azure data types.
    result = [
        max(
            [
                metric_value.maximum
                for ts in metric.timeseries
                for metric_value in ts.data
                if metric_value.maximum is not None
            ],
            default = 0
        )
        for metric in metrics_data.value
    ]
    return 0 if len(result) == 0 else result[0]


def get_resource_group(cluster):
    return cluster.id.split("/")[4]


def process_cluster(cluster, mc):
    print(".", end="")

    # replicas per master is not reported by api for basic and standard tiers and for premium with default of one replica
    replicas_per_master = {
        'Basic': 0,
        'Standard' : 1,
        'Premium': getattr(cluster, 'replicas_per_master', 0) or 1,
        'Enterprise_E1': 1,
        'Enterprise_E5': 1,
        'Enterprise_E10': 1,
        'Enterprise_E20': 1,
        'Enterprise_E50': 1,
        'Enterprise_E100': 1,
        'Enterprise_E200': 1,
        'Enterprise_E400': 1
    }.get(cluster.sku.name)

    cluster_rows = []

    if cluster.type == 'Microsoft.Cache/redisEnterprise' and cluster.sku.name not in amrClusterInfo['SKU']:
        cluster_info = lookup_enterprise_sku_capcity(cluster.sku.name, cluster.sku.capacity)
        cluster_shard_count = 1

        non_metrics = [
            get_resource_group(cluster),
            cluster.location,
            cluster.name,
            f"{cluster.sku.name.split('_')[-1]}-Capacity{cluster.sku.capacity}",
            f"{cluster.sku.name.rsplit('_', 1)[0]}",
            replicas_per_master,
            cluster_info['MasterShards']
        ]

        shard_ops_metrics = round(get_max_metrics(mc, cluster.id, f"operationspersecond"), 0)
        shard_memory_metrics = round(get_max_metrics(mc, cluster.id, f"usedmemory") / 1024 / 1024, 2) #bytes to megabytes
        shard_connection_metrics = get_max_metrics(mc, cluster.id, f"connectedclients")
        cluster_rows.append(non_metrics + [0, shard_ops_metrics, shard_memory_metrics, shard_connection_metrics])  

    if cluster.type == 'Microsoft.Cache/Redis':
        cluster_shard_count = cluster.shard_count or 1 # api returns empty string if shard count is 1

        non_metrics = [
            get_resource_group(cluster),
            cluster.location,
            cluster.name,
            f"{cluster.sku.family}{cluster.sku.capacity}",
            f"{cluster.sku.name}",
            replicas_per_master,
            cluster_shard_count
        ]

        for shard_id in range(cluster_shard_count):
            shard_ops_metrics = round(get_max_metrics(mc, cluster.id, f"operationspersecond{shard_id}"), 0)
            shard_memory_metrics = round(get_max_metrics(mc, cluster.id, f"usedmemory{shard_id}") / 1024 / 1024, 2) #bytes to megabytes
            shard_connection_metrics = get_max_metrics(mc, cluster.id, f"connectedclients{shard_id}")
            cluster_rows.append(non_metrics + [shard_id, shard_ops_metrics, shard_memory_metrics, shard_connection_metrics])   

    return cluster_rows


def get_subscription_info(credential):
    print("Gathering subscription information...")
    return [[sub.subscription_id, MonitorManagementClient(
            credential=credential,
            subscription_id=sub.subscription_id
            )]
            for sub in
            SubscriptionClient(credential=credential).subscriptions.list()]


def list_clusters(credential, subscription_id, pullAcre):
    print(f"Gathering cluster information for subscription {subscription_id}")

    oss_clusters = list(RedisManagementClient(credential, subscription_id).redis.list())
    
    enterprise_clusters = []

    if pullAcre:
        enterprise_clusters = list(RedisEnterpriseManagementClient(credential, subscription_id).redis_enterprise.list())

    return oss_clusters, enterprise_clusters


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--out-dir", dest="outDir", default=".",
                        help="directory to write the results in",
                        metavar="PATH")
    
    parser.add_argument("-e", "--pullAcre", action='store_true', help='Pull acre clusters')

    args = parser.parse_args()
    output_file_path = Path(args.outDir) / "AzureStats.xlsx"

    tenant_id = os.getenv('AZURE_TENANT_ID')  # Set this environment variable

    azure_credential = DefaultAzureCredential()

    metrics = [[sub_info[0]] + shard_stats
               for sub_info in get_subscription_info(azure_credential)
               for oss_clusters, enterprise_clusters in [list_clusters(azure_credential, sub_info[0], args.pullAcre)]
               for cluster in oss_clusters + enterprise_clusters
               for shard_stats in process_cluster(cluster, sub_info[1])]

    df = pd.DataFrame(metrics, columns=["Subscription ID",
                                        "Resource Group",
                                        "Region",
                                        "DB Name",
                                        "SKU Capacity",
                                        "SKU Name",
                                        "Replicas per Master",
                                        "Shard Count",
                                        "Shard Number",
                                        "Avg Ops/Sec",
                                        "Used Memory (MB)",
                                        "Max Total Connections"])

    with (pd.ExcelWriter(output_file_path, engine='xlsxwriter')) as writer:
        df.to_excel(writer, 'ClusterData', index=False)

    print("\r\nResults are in {}".format(output_file_path))


if __name__ == "__main__":
    main()
