#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../ha/common.sh"
FAILURE_RUNTIME="$PGSENTRY_RUNTIME/results/m5"
failure_load() { load_profile "$1"; mkdir -p "$FAILURE_RUNTIME"; chmod 700 "$FAILURE_RUNTIME"; }
backend_name() { ssh_node "$CONTROL_IP" "echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock" | awk -F, '$1=="patroni_primary"&&$2!="BACKEND"&&$18=="UP"{print $2}'; }
etcd_healthy_count() { source "$PGSENTRY_ROOT/scripts/etcd/common.sh"; load_profile "$1"; healthy_count; }
monotonic_ns() { ssh_node "$CONTROL_IP" "python3 -c 'import time; print(time.monotonic_ns())'"; }
wait_new_leader() { local old=$1 now; for _ in $(seq 1 75); do now=$(leader_name 2>/dev/null || true); [[ -n $now && $now != "$old" ]] && { echo "$now"; return; }; sleep 1; done; return 1; }
wait_haproxy_primary() { local name=$1; for _ in $(seq 1 60); do [[ $(backend_name 2>/dev/null || true) == "$name" ]] && return; sleep 1; done; return 1; }
wait_workload_successes() { local file=$1 minimum=$2; for _ in $(seq 1 40); do [[ -f $file ]] && [[ $(jq -s '[.[]|select(.outcome=="confirmed_success")]|length' "$file") -ge $minimum ]] && return; sleep 1; done; return 1; }
wait_success_after() { local file=$1 timestamp=$2; for _ in $(seq 1 90); do [[ -f $file ]] && [[ $(jq -s --argjson t "$timestamp" '[.[]|select(.outcome=="confirmed_success" and .attempt_completed_ns >= $t)]|length' "$file") -ge 1 ]] && return; sleep 1; done; return 1; }
classify_rejoin() { local ip=$1 since=$2 logs; logs=$(ssh_node "$ip" "sudo journalctl -u patroni --since '@$since' --no-pager"); if grep -qi pg_rewind <<<"$logs"; then echo pg_rewind; elif grep -Eqi 'reinitialize|base backup|pg_basebackup' <<<"$logs"; then echo full_reinitialization; elif grep -qi 'starting as a secondary' <<<"$logs" || { grep -qi 'new target timeline' <<<"$logs" && grep -qi 'following a leader' <<<"$logs"; }; then echo normal_timeline_catchup; else echo not_applicable; fi; }
assert_no_isolation() { for ip in "${PG_IPS[@]}"; do ! ssh_node "$ip" "sudo iptables-save | grep -q pgsentry-m5-dcs-isolation"; done; }
