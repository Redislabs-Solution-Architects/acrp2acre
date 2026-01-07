# Bash / Cloud Shell Redis Metrics Script

This directory contains a **Bash-based alternative** to `pullAzureCacheForRedisStats.py`, designed for environments where Python or Azure SDK compatibility is an issue (e.g. **Azure Cloud Shell**).

The script uses **Azure CLI + Azure Monitor** and produces a CSV report suitable for Excel-based analysis.

---

## What the script does

- Detects **Azure Cache for Redis (OSS)** and **Redis Enterprise (ACRE)**
- Automatically skips ACRE if none are present
- Excludes **Azure Managed Redis (AMR)** SKUs from the ACRE section
- Collects **30 days** of metrics with **hourly granularity**
- Outputs a single CSV file

---

## Intended environment

This script is intended to be run in **Azure Cloud Shell (Bash)**.

Cloud Shell already includes all required dependencies: az, jq, timeout, and GNU date.

Running the script locally (e.g. Git Bash on Windows) requires installing jq and is not the primary supported path.

---

## Prerequisites

- Azure Cloud Shell (Bash)
- Logged in via az login
- Permissions to list Redis resources and read Azure Monitor metrics

---

## How to run (Azure Cloud Shell)

1. Open Azure Portal → Cloud Shell → Bash
2. Navigate to the repository root
3. Make the script executable: chmod +x bash/pull_redis_stats.sh
4. Run the script: ./bash/pull_redis_stats.sh AzureStats.csv

During execution:
- OSS runs silently
- ACRE displays progress dots (.) so it does not appear frozen

When complete, you will see: Wrote AzureStats.csv

5. Download the file using the Cloud Shell Download button and open it in Excel.

---

## Output columns

- Subscription ID
- Resource Group
- Region
- DB Name
- SKU Capacity
- SKU Name
- Replicas per Master
- Shard Count
- Shard Number
- Max Ops/Sec
- Used Memory (MB)
- Max Total Connections

---

## Notes

- The script intentionally produces CSV (not XLSX) to avoid Python dependencies.
- Metric values represent maximum hourly values over the collection window.
- Large tenants may take several minutes due to Azure Monitor rate limits.

---

## Relationship to the Python script

This script is functionally equivalent to pullAzureCacheForRedisStats.py for inventory and sizing analysis, but implemented using Azure CLI to maximize compatibility in Cloud Shell environments.
