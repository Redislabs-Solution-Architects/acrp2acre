from azure.identity import DefaultAzureCredential
from azure.mgmt.redis import RedisManagementClient
from azure.mgmt.monitor import MonitorManagementClient
from azure.mgmt.subscription import SubscriptionClient
import datetime
import pandas as pd
from pathlib import Path
import argparse

# The measurement collection period in days.
METRIC_COLLECTION_PERIOD_DAYS = 7

# The aggregation period
# (see https://en.wikipedia.org/wiki/ISO_8601#Durations )
AGGREGATION_PERIOD = "PT1H"

# Seconds in the aggregation period
SECONDS_PER_AGGREGATION_PERIOD = 3600

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

    # replicas per master is not reported by api for basic and standard tiers amd for premium with default of one replica
    replicas_per_master = {
        'Basic': 0,
        'Standard' : 1,
        'Premium': cluster.replicas_per_master or 1
    }[cluster.sku.name]

    non_metrics = [
        get_resource_group(cluster),
        cluster.name,
        cluster.sku.name,
        replicas_per_master,
        cluster.shard_count or 1 # api returns empty string if shard count is 1
    ]
    total_metrics = round(get_max_average_metrics(mc, cluster.id, "operationspersecond0,operationspersecond1"), 0)
    memory_metrics = round(get_max_metrics(mc, cluster.id, "usedmemory") / 1024 / 1024, 2) #bytes to megabytes
    connection_metrics = get_max_metrics(mc, cluster.id, "connectedclients")
    return non_metrics + [total_metrics, memory_metrics, connection_metrics]


def get_subscription_info(credential):
    return [[sub.subscription_id, MonitorManagementClient(
            credential=credential,
            subscription_id=sub.subscription_id
            )]
            for sub in
            SubscriptionClient(credential=credential).subscriptions.list()]


def list_clusters(credential, subscription_id):
    return RedisManagementClient(credential, subscription_id).redis.list()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--out-dir", dest="outDir", default=".",
                        help="directory to write the results in",
                        metavar="PATH")
    args = parser.parse_args()
    output_file_path = Path(args.outDir) / "AzureStats.xlsx"

    azure_credential = DefaultAzureCredential()
    metrics = [[sub_info[0]] + process_cluster(cluster, sub_info[1])
               for sub_info in get_subscription_info(azure_credential)
               for cluster in list_clusters(azure_credential, sub_info[0])]
    df = pd.DataFrame(metrics, columns=["Subscription ID",
                                        "Resource Group",
                                        "DB Name",
                                        "SKU",
                                        "Replicas per Master",
                                        "Shard Count",
                                        "Avg Ops/Sec",
                                        "Used Memory (MB)",
                                        "Max Total Connections"])

    with (pd.ExcelWriter(output_file_path, engine='xlsxwriter')) as writer:
        df.to_excel(writer, 'ClusterData', index=False)

    print("Results are in {}".format(output_file_path))


if __name__ == "__main__":
    main()
