#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; load_profile "${1:-}"; wait_cluster
json=$(cluster_json); [[ $(jq 'length' <<<"$json") -eq 3 ]]; [[ $(jq '[.[]|select(.Role=="Leader")]|length' <<<"$json") -eq 1 ]]; [[ $(jq '[.[]|select(.Role|test("Replica"))]|length' <<<"$json") -eq 2 ]]
leader=$(leader_name); leader_ip=$(name_ip "$leader")
[[ $(sql "$leader_ip" 'SELECT pg_is_in_recovery()') == f ]]
for i in 0 1 2; do ip=${PG_IPS[$i]}; name=${PG_NAMES[$i]}; curl -fsS --max-time 5 "http://$ip:8008/health" >/dev/null; if [[ $name != "$leader" ]]; then [[ $(sql "$ip" 'SELECT pg_is_in_recovery()') == t ]]; fi; done
[[ $(sql "$leader_ip" "SELECT count(*) FROM pg_stat_replication WHERE state='streaming'") -eq 2 ]]
value="m4-before-failover-$(date -u +%Y%m%dT%H%M%SZ)"; sql "$leader_ip" "CREATE TABLE IF NOT EXISTS public.m4_evidence(value text PRIMARY KEY, created_at timestamptz default now()); INSERT INTO public.m4_evidence(value) VALUES('$value');" >/dev/null
for ip in "${PG_IPS[@]}"; do wait_value "$ip" "$value"; done
source "$PGSENTRY_ROOT/scripts/etcd/common.sh"; load_profile "${1:-}"; dcs=$(etcdctl_cmd get /pgsentry/m4/ --prefix --keys-only); grep -q '/leader' <<<"$dcs"; grep -q '/members/' <<<"$dcs"
patronictl list; echo "leader=$leader leader_ip=$leader_ip replicated_value=$value observed=3/3"
