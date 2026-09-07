#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; observability_load "${1:-}"; scenario=${2:-}
wait_cluster; wait_metric pgsentry_postgresql_primary_count 1; wait_metric pgsentry_postgresql_replica_count 2; wait_metric pgsentry_etcd_healthy_members 3; wait_metric pgsentry_haproxy_writable_backends 1
cleanup() { set +e; [[ -n ${target_ip:-} && -n ${service:-} ]] && ssh_node "$target_ip" "sudo systemctl start $service"; [[ -n ${replay_pid:-} && -n ${paused_ip:-} ]] && ssh_node "$paused_ip" "sudo kill -CONT '$replay_pid'"; [[ -n ${paused_ip:-} ]] && sql "$paused_ip" 'SELECT pg_wal_replay_resume()' >/dev/null; wait_cluster >/dev/null 2>&1; }
trap cleanup EXIT INT TERM
case "$scenario" in
  replica-loss)
    target=$(cluster_json | jq -r '.[]|select(.Role!="Leader")|.Member' | head -1); target_ip=$(name_ip "$target"); service=patroni; alert=PgSentryReplicaCountLow; metric=pgsentry_postgresql_replica_count
    evidence_event "$scenario" injected "$metric" 2 "$alert"; ssh_node "$target_ip" 'sudo systemctl stop patroni'; wait_metric "$metric" 1; wait_alert "$alert" firing; wait_alertmanager "$alert" firing; evidence_event "$scenario" firing "$metric" 1 "$alert"
    [[ $(prom_query pgsentry_postgresql_primary_count) == 1 ]]; ssh_node "$target_ip" 'sudo systemctl start patroni'; service=; wait_cluster; wait_metric "$metric" 2; wait_alert "$alert" resolved; wait_alertmanager "$alert" resolved
    ;;
  etcd-member-loss)
    target_ip=${ETCD_IPS[2]}; service=etcd; alert=PgSentryEtcdMemberDown; metric=pgsentry_etcd_healthy_members
    evidence_event "$scenario" injected "$metric" 3 "$alert"; ssh_node "$target_ip" 'sudo systemctl stop etcd'; wait_metric "$metric" 2; wait_alert "$alert" firing; wait_alertmanager "$alert" firing; evidence_event "$scenario" firing "$metric" 2 "$alert"
    [[ $(prom_query pgsentry_postgresql_primary_count) == 1 ]]; ssh_node "$target_ip" 'sudo systemctl start etcd'; service=; wait_metric "$metric" 3; wait_alert "$alert" resolved; wait_alertmanager "$alert" resolved
    ;;
  haproxy-loss)
    target_ip=$CONTROL_IP; service=haproxy; alert=PgSentryHAProxyDown; metric='up{job="haproxy"}'
    evidence_event "$scenario" injected "$metric" 1 "$alert"; ssh_node "$target_ip" 'sudo systemctl stop haproxy'; wait_metric "$metric" 0; wait_alert "$alert" firing; wait_alertmanager "$alert" firing; evidence_event "$scenario" firing "$metric" 0 "$alert"
    [[ $(prom_query pgsentry_postgresql_primary_count) == 1 ]]; ssh_node "$target_ip" 'sudo systemctl start haproxy'; service=; wait_metric "$metric" 1; wait_metric pgsentry_haproxy_writable_backends 1; wait_alert "$alert" resolved; wait_alertmanager "$alert" resolved
    ;;
  replication-lag)
    target=$(cluster_json | jq -r '.[]|select(.Role!="Leader")|.Member' | head -1); paused_ip=$(name_ip "$target"); alert=PgSentryReplicationLagHigh; metric=pgsentry_replication_lag_bytes
    replay_pid=$(ssh_node "$paused_ip" "pgrep -f '^postgres: pgsentry: startup recovering' | head -1")
    [[ -n $replay_pid ]] || { echo 'standby recovery process not found' >&2; exit 1; }
    ssh_node "$paused_ip" "sudo kill -STOP '$replay_pid'"
    leader_ip=$(current_leader_ip); sql "$leader_ip" "CREATE TABLE IF NOT EXISTS public.m10_lag(payload text); INSERT INTO public.m10_lag SELECT repeat(md5(g::text),64) FROM generate_series(1,10000) g" >/dev/null
    for _ in $(seq 1 40); do [[ $(prom_query "$metric" | cut -d. -f1) -gt 1048576 ]] && break; sleep 3; done
    wait_alert "$alert" firing; wait_alertmanager "$alert" firing; evidence_event "$scenario" firing "$metric" "$(prom_query "$metric")" "$alert"; ssh_node "$paused_ip" "sudo kill -CONT '$replay_pid'"; replay_pid=; paused_ip=; wait_cluster
    for _ in $(seq 1 60); do [[ $(prom_query "$metric" | cut -d. -f1) -lt 1048576 ]] && break; sleep 3; done
    wait_alert "$alert" resolved; wait_alertmanager "$alert" resolved; sql "$leader_ip" 'DROP TABLE IF EXISTS public.m10_lag' >/dev/null
    ;;
  *) echo 'ALERT_TEST must be replica-loss, etcd-member-loss, haproxy-loss, or replication-lag' >&2; exit 2 ;;
esac
evidence_event "$scenario" resolved "$metric" "$(prom_query "$metric" 2>/dev/null || true)" "$alert"
echo "$scenario alert lifecycle passed"
