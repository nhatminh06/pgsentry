#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../durability/common.sh"
CHAOS_RUNTIME="$PGSENTRY_RUNTIME/results/m7"; CHAOS_TAG=pgsentry-m7-chaos
chaos_load() { durability_load "$1"; mkdir -p "$CHAOS_RUNTIME"; chmod 700 "$CHAOS_RUNTIME"; }
run_bounded() {
  local label=$1 seconds=$2 pid rc
  shift 2
  echo "chaos_baseline_stage=$label status=running" >&2
  "$@" & pid=$!
  for _ in $(seq 1 "$seconds"); do
    kill -0 "$pid" 2>/dev/null || {
      if wait "$pid"; then rc=0; else rc=$?; fi
      if (( rc == 0 )); then
        echo "chaos_baseline_stage=$label status=passed" >&2
      else
        echo "chaos_baseline_stage=$label status=failed exit_code=$rc" >&2
      fi
      return "$rc"
    }
    sleep 1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "chaos_baseline_stage=$label status=timed_out timeout_seconds=$seconds" >&2
  return 124
}
assert_no_chaos_rules() { local ip; for ip in "${PG_IPS[@]}" "${ETCD_IPS[@]}"; do ! ssh_node "$ip" "sudo iptables-save | grep -q '$CHAOS_TAG'"; done; }
observe_roles() {
  local output=$1 count=0 roles='{}' role i
  for i in 0 1 2; do role=$(sql "${PG_IPS[$i]}" 'select pg_is_in_recovery()' 2>/dev/null || echo unavailable); [[ $role == f ]] && count=$((count+1)); roles=$(jq -c --arg n "${PG_NAMES[$i]}" --arg r "$role" '.+{($n):$r}' <<<"$roles"); done
  jq -cn --argjson timestamp_ns "$(monotonic_ns)" --argjson writable "$count" --argjson roles "$roles" '{timestamp_ns:$timestamp_ns,writable_primary_count:$writable,roles:$roles}' >>"$output"
  (( count <= 1 )) || { echo 'safety violation: multiple writable primaries observed' >&2; return 1; }
}
max_writable() { jq -s 'map(.writable_primary_count)|max // 0' "$1"; }
