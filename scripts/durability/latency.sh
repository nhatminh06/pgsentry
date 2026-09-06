#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
profile=${1:-}; mode=${2:-}; validate_mode "$mode"; durability_load "$profile"; "$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" "$mode" --quiet
run_id="latency-$mode-$(date -u +%Y%m%dT%H%M%SZ)"; dir="$DURABILITY_RUNTIME/$run_id"; mkdir -p "$dir"; events="$dir/workload.jsonl"; stop="/tmp/$run_id.stop"; remote="/tmp/$run_id-workload.py"
start_workload "$run_id" "$events" "$stop" "$remote" "$mode"; wait_workload_successes "$events" 40; stop_workload "$stop" "$remote"
metrics=$(python3 "$PGSENTRY_ROOT/scripts/durability/latency.py" "$events")
jq -cn --arg policy "$mode" --arg scenario healthy-latency --arg run_id "$run_id" --argjson metrics "$metrics" '{policy:$policy,scenario:$scenario,run_id:$run_id,result:"passed"}+$metrics' | tee "$dir/result.json"
