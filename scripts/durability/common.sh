#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../failures/common.sh"
DURABILITY_RUNTIME="$PGSENTRY_RUNTIME/results/m6"
durability_load() { load_profile "$1"; mkdir -p "$DURABILITY_RUNTIME"; chmod 700 "$DURABILITY_RUNTIME"; }
validate_mode() { case "$1" in async|sync|sync-strict) ;; *) echo 'MODE must be async, sync, or sync-strict' >&2; return 2;; esac; }
dynamic_config() {
  local yaml encoded
  yaml=$(patronictl show-config); encoded=$(printf %s "$yaml" | base64 -w0)
  ssh_node "${PG_IPS[0]}" "printf %s '$encoded' | base64 -d | sudo /opt/patroni/bin/python -c 'import json,sys,yaml; print(json.dumps(yaml.safe_load(sys.stdin)))'"
}
replication_json() {
  local leader ip
  leader=$(leader_name); ip=$(name_ip "$leader")
  sql "$ip" "select coalesce(json_agg(x),'[]') from (select application_name,state,sync_state,sync_priority,write_lsn,flush_lsn,replay_lsn from pg_stat_replication order by application_name) x"
}
sync_standby() { replication_json | jq -r '.[]|select(.sync_state=="sync")|.application_name' | head -1; }
wait_policy() { local mode=$1; for _ in $(seq 1 40); do "$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" "$mode" --quiet 2>/dev/null && return; sleep 2; done; "$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" "$mode"; }
start_workload() {
  local run_id=$1 events=$2 remote_stop=$3 remote_workload=$4 policy=$5 password encoded
  password=$(runtime_secret superuser-password); encoded=$(base64 -w0 "$PGSENTRY_ROOT/scripts/failures/workload.py")
  ssh_node "$CONTROL_IP" "printf %s '$encoded' | base64 -d >'$remote_workload'; rm -f '$remote_stop'"
  printf '%s\n' "$password" | ssh_node "$CONTROL_IP" "IFS= read -r PGPASSWORD; export PGPASSWORD; python3 '$remote_workload' --host 127.0.0.1 --port '$HAPROXY_WRITE_PORT' --run-id '$run_id' --policy '$policy' --events /dev/stdout --stop-file '$remote_stop'" >"$events" &
  WORKLOAD_PID=$!
}
stop_workload() { local stop=$1 remote=$2; ssh_node "$CONTROL_IP" "touch '$stop'"; wait "$WORKLOAD_PID"; ssh_node "$CONTROL_IP" "rm -f '$stop' '$remote'"; }
