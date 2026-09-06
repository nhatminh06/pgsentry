#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; profile=${1:-}; failure_load "$profile"
wait_cluster
state=$(cluster_json); [[ $(jq 'length' <<<"$state") -eq 3 ]]
leader=$(leader_name); leader_ip=$(name_ip "$leader")
[[ $(sql "$leader_ip" 'select pg_is_in_recovery()') == f ]]
[[ $(sql "$leader_ip" "select count(*) from pg_stat_replication where state='streaming'") -eq 2 ]]
for i in 0 1 2; do [[ ${PG_NAMES[$i]} == "$leader" ]] || [[ $(sql "${PG_IPS[$i]}" 'select pg_is_in_recovery()') == t ]]; done
[[ $(etcd_healthy_count "$profile") -eq 3 ]]
[[ $(backend_name) == "$leader" ]]
haproxy_sql 'create table if not exists public.m5_probe(run_id text not null,seq bigint not null,client_sent_at timestamptz not null,server_committed_at timestamptz default clock_timestamp(),primary key(run_id,seq));' >/dev/null
probe="m5-baseline-$(date -u +%Y%m%dT%H%M%SZ)"; haproxy_sql "insert into public.m5_probe(run_id,seq,client_sent_at) values('$probe',1,clock_timestamp())" >/dev/null
assert_no_isolation
echo "baseline=healthy leader=$leader backend=$(backend_name) etcd=3/3 client_write=$probe"
