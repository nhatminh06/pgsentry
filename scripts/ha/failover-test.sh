#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; load_profile "${1:-}"
stopped_patroni= stopped_etcd=
cleanup() { [[ -z $stopped_patroni ]] || ssh_node "$stopped_patroni" 'sudo systemctl start patroni' || true; [[ -z $stopped_etcd ]] || ssh_node "$stopped_etcd" 'sudo systemctl start etcd' || true; }
trap cleanup EXIT INT TERM
wait_cluster; old=$(leader_name); old_ip=$(name_ip "$old"); before=$(date +%s); echo "old_primary=$old ip=$old_ip"
ssh_node "$old_ip" 'sudo systemctl stop patroni'; stopped_patroni=$old_ip
new=
for _ in $(seq 1 60); do new=$(leader_name 2>/dev/null || true); [[ -n $new && $new != "$old" ]] && break; sleep 2; done
[[ -n $new && $new != "$old" ]]; new_ip=$(name_ip "$new"); promoted=$(date +%s); [[ $(sql "$new_ip" 'SELECT pg_is_in_recovery()') == f ]]
for _ in $(seq 1 30); do routed=$(haproxy_sql 'SELECT inet_server_addr()' 2>/dev/null || true); [[ $routed == "$new_ip" ]] && break; sleep 2; done
[[ $routed == "$new_ip" ]]; routed_at=$(date +%s)
value="m4-haproxy-after-failover-$(date -u +%Y%m%dT%H%M%SZ)"; haproxy_sql "INSERT INTO public.m4_evidence(value) VALUES('$value')" >/dev/null
for i in 0 1 2; do [[ ${PG_IPS[$i]} != "$old_ip" ]] && wait_value "${PG_IPS[$i]}" "$value"; done
ssh_node "$old_ip" 'sudo systemctl start patroni'; stopped_patroni=; wait_cluster; wait_value "$old_ip" "$value"
[[ $(sql "$old_ip" 'SELECT pg_is_in_recovery()') == t ]]
logs=$(ssh_node "$old_ip" "sudo journalctl -u patroni --since '@$before' --no-pager")
if grep -qi 'pg_rewind' <<<"$logs"; then
  rejoin=pg_rewind
elif grep -qi 'starting as a secondary' <<<"$logs" && grep -qi 'new target timeline' <<<"$logs"; then
  rejoin=normal_timeline_catchup
elif grep -Eqi 'reinitialize|base backup|pg_basebackup' <<<"$logs"; then
  rejoin=full_reinitialization
else
  echo 'Unable to classify former-primary rejoin from Patroni logs' >&2
  exit 1
fi
etcd_ip=${ETCD_IPS[0]}; ssh_node "$etcd_ip" 'sudo systemctl stop etcd'; stopped_etcd=$etcd_ip
sleep 3; wait_cluster; [[ $(haproxy_sql 'SELECT pg_is_in_recovery()') == f ]]
ssh_node "$etcd_ip" 'sudo systemctl start etcd'; stopped_etcd=; source "$PGSENTRY_ROOT/scripts/etcd/common.sh"; load_profile "${1:-}"; wait_healthy 3
echo "new_primary=$new routed_server=$routed post_value=$value rejoin=$rejoin election_observed_seconds=$((promoted-before)) routing_observed_seconds=$((routed_at-before)) etcd_one_member_loss=passed"
