#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; load_profile "${1:-}"; wait_cluster
leader=$(leader_name); leader_ip=$(name_ip "$leader")
for _ in $(seq 1 30); do routed=$(haproxy_sql 'SELECT inet_server_addr()' 2>/dev/null || true); [[ $routed == "$leader_ip" ]] && break; sleep 2; done
[[ $routed == "$leader_ip" ]]; [[ $(haproxy_sql 'SELECT pg_is_in_recovery()') == f ]]
stats=$(ssh_node "$CONTROL_IP" "echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock")
[[ $(awk -F, '$1=="patroni_primary" && $2!="BACKEND" && $18=="UP"{n++} END{print n+0}' <<<"$stats") -eq 1 ]]
value="m4-haproxy-before-failover-$(date -u +%Y%m%dT%H%M%SZ)"; haproxy_sql "CREATE TABLE IF NOT EXISTS public.m4_evidence(value text PRIMARY KEY, created_at timestamptz default now()); INSERT INTO public.m4_evidence(value) VALUES('$value');" >/dev/null
for ip in "${PG_IPS[@]}"; do wait_value "$ip" "$value"; done
echo "haproxy_backend=$leader routed_server=$routed recovery=false value=$value observed=3/3"
