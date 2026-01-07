#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Config
# -----------------------------
METRIC_DAYS=30                 # changed from 90 -> 30
INTERVAL="PT1H"
OUT="${1:-AzureStats.csv}"     # pass output file path as first arg (default AzureStats.csv)

# Optional safety: prevent any single metrics call from hanging forever (seconds)
METRICS_TIMEOUT_SECONDS=180

# AMR SKUs show up under redisEnterprise too; exclude them from the ACRE section
AMR_SKU_REGEX='^(GeneralPurpose_G|Balanced_B|MemoryOptimized_M|ComputeOptimized_X|FlashOptimized_A)'

# -----------------------------
# Dependencies
# -----------------------------
command -v az >/dev/null || { echo "ERROR: az cli not found"; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq not found (Cloud Shell usually has it)"; exit 1; }
command -v timeout >/dev/null || { echo "ERROR: timeout not found"; exit 1; }

# -----------------------------
# Time window (UTC)
# -----------------------------
START_TIME="$(date -u -d "${METRIC_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)"
END_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -----------------------------
# Helpers
# -----------------------------
csv_escape() {
  local s="$1"
  s="${s//\"/\"\"}"
  printf "\"%s\"" "$s"
}

max_metric() {
  # Args: resourceId metricName aggregation(Maximum|Average)
  local rid="$1" metric="$2" agg="$3"

  # If the metrics call fails/times out, return 0 (so the run continues)
  timeout "${METRICS_TIMEOUT_SECONDS}" az monitor metrics list \
    --resource "$rid" \
    --metric "$metric" \
    --aggregation "$agg" \
    --interval "$INTERVAL" \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    -o json 2>/dev/null |
    jq -r '
      (.value // []) as $v
      | if ($v|length)==0 then 0
        else
          [
            $v[]
            | .timeseries[]
            | .data[]
            | if "'"$agg"'"=="Maximum" then .maximum else .average end
            | select(. != null)
          ]
          | max // 0
        end
    ' || echo 0
}

replicas_per_master_oss() {
  # Args: skuName replicasPerMaster(from resource, may be null/0)
  local skuName="$1" rpm="${2:-0}"
  case "$skuName" in
    Basic)    echo 0 ;;
    Standard) echo 1 ;;
    Premium)
      # Python defaults Premium to 1 when missing/0
      if [[ -z "${rpm}" || "${rpm}" == "0" ]]; then echo 1; else echo "$rpm"; fi
      ;;
    *) echo 1 ;;
  esac
}

# -----------------------------
# Output header
# -----------------------------
{
  echo "Subscription ID,Resource Group,Region,DB Name,SKU Capacity,SKU Name,Replicas per Master,Shard Count,Shard Number,Max Ops/Sec,Used Memory (MB),Max Total Connections"
} > "$OUT"

# -----------------------------
# Iterate subscriptions
# -----------------------------
mapfile -t SUBS < <(az account list --query "[].id" -o tsv)

for SUB in "${SUBS[@]}"; do
  az account set --subscription "$SUB" >/dev/null

  # -----------------------------------------
  # OSS: Microsoft.Cache/Redis (az redis list)
  # -----------------------------------------
  mapfile -t OSS < <(
    az redis list -o json |
      jq -r '.[] | [
        .resourceGroup,
        .location,
        .name,
        (.sku.family // ""),
        (.sku.capacity // 0),
        (.sku.name // ""),
        (.replicasPerMaster // 0),
        (.shardCount // 1),
        .id
      ] | @tsv'
  )

  for row in "${OSS[@]}"; do
    IFS=$'\t' read -r RG REGION NAME SKUFAM SKUCAP SKUNAME RPM SHARDS RID <<<"$row"
    [[ -z "${SHARDS:-}" || "${SHARDS:-0}" -lt 1 ]] && SHARDS=1

    RPM_CALC="$(replicas_per_master_oss "$SKUNAME" "$RPM")"
    SKU_CAPACITY_FMT="${SKUFAM}${SKUCAP}"   # matches python: f"{family}{capacity}"
    SKU_NAME_FMT="${SKUNAME}"

    for ((sh=0; sh<SHARDS; sh++)); do
      OPS="$(max_metric "$RID" "operationspersecond${sh}" "Maximum")"
      MEM_BYTES="$(max_metric "$RID" "usedmemory${sh}" "Maximum")"
      CONN="$(max_metric "$RID" "connectedclients${sh}" "Maximum")"

      MEM_MB="$(awk -v b="$MEM_BYTES" 'BEGIN { printf "%.2f", (b/1024/1024) }')"
      OPS_ROUND="$(awk -v x="$OPS" 'BEGIN { printf "%.0f", x }')"

      printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "$(csv_escape "$SUB")" \
        "$(csv_escape "$RG")" \
        "$(csv_escape "$REGION")" \
        "$(csv_escape "$NAME")" \
        "$(csv_escape "$SKU_CAPACITY_FMT")" \
        "$(csv_escape "$SKU_NAME_FMT")" \
        "$(csv_escape "$RPM_CALC")" \
        "$(csv_escape "$SHARDS")" \
        "$(csv_escape "$sh")" \
        "$(csv_escape "$OPS_ROUND")" \
        "$(csv_escape "$MEM_MB")" \
        "$(csv_escape "$CONN")" \
        >> "$OUT"
    done
  done

  # ----------------------------------------------------
  # ACRE: Microsoft.Cache/redisEnterprise (AUTO-DETECTED)
  # Excludes AMR SKUs that also appear under redisEnterprise
  # ----------------------------------------------------
  mapfile -t ACRE < <(
    az resource list --resource-type "Microsoft.Cache/redisEnterprise" -o json |
      jq -r --arg re "$AMR_SKU_REGEX" '
        .[]
        | select((.sku.name // "") | test($re) | not)
        | [
            .resourceGroup,
            .location,
            .name,
            (.sku.name // ""),
            (.sku.capacity // 0),
            .id
          ]
        | @tsv
      '
  )

  if (( ${#ACRE[@]} > 0 )); then
    # progress dots so it doesn’t look frozen
    for row in "${ACRE[@]}"; do
      echo -n "."
      IFS=$'\t' read -r RG REGION NAME SKUNAME SKUCAP RID <<<"$row"

      # Matches python formatting:
      # SKU Capacity: "{suffix}-Capacity{capacity}" (suffix = last token after underscore)
      # SKU Name: base before last underscore
      SKU_CAPACITY_FMT="$(awk -v s="$SKUNAME" -v c="$SKUCAP" 'BEGIN{
        n=split(s,a,"_"); print a[n] "-Capacity" c
      }')"
      SKU_NAME_FMT="$(awk -v s="$SKUNAME" 'BEGIN{
        sub(/_[^_]+$/,"",s); print s
      }')"

      RPM_CALC=1
      SHARDS=1

      OPS="$(max_metric "$RID" "operationspersecond" "Maximum")"
      MEM_BYTES="$(max_metric "$RID" "usedmemory" "Maximum")"
      CONN="$(max_metric "$RID" "connectedclients" "Maximum")"

      MEM_MB="$(awk -v b="$MEM_BYTES" 'BEGIN { printf "%.2f", (b/1024/1024) }')"
      OPS_ROUND="$(awk -v x="$OPS" 'BEGIN { printf "%.0f", x }')"

      printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "$(csv_escape "$SUB")" \
        "$(csv_escape "$RG")" \
        "$(csv_escape "$REGION")" \
        "$(csv_escape "$NAME")" \
        "$(csv_escape "$SKU_CAPACITY_FMT")" \
        "$(csv_escape "$SKU_NAME_FMT")" \
        "$(csv_escape "$RPM_CALC")" \
        "$(csv_escape "$SHARDS")" \
        "$(csv_escape "0")" \
        "$(csv_escape "$OPS_ROUND")" \
        "$(csv_escape "$MEM_MB")" \
        "$(csv_escape "$CONN")" \
        >> "$OUT"
    done
    echo
  fi

done

echo "Wrote $OUT"
