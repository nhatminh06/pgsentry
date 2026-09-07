#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; observability_load "${1:-}"
wait_metric 'pgsentry_postgresql_primary_count' 1
wait_metric 'pgsentry_postgresql_replica_count' 2
wait_metric 'pgsentry_etcd_healthy_members' 3
wait_metric 'pgsentry_haproxy_writable_backends' 1
targets=$(ssh_node "$CONTROL_IP" "curl -fsS http://127.0.0.1:$PROMETHEUS_PORT/api/v1/targets")
down=$(jq '[.data.activeTargets[]|select(.health!="up")]|length' <<<"$targets")
expected=$(jq '[.data.activeTargets[]]|length' <<<"$targets")
[[ $down -eq 0 && $expected -eq 15 ]] || { jq '.data.activeTargets[]|select(.health!="up")|{scrapeUrl,lastError}' <<<"$targets"; echo "expected 15 UP targets, got $expected total / $down down" >&2; exit 1; }
backup=$(prom_query 'pgsentry_backup_last_success_timestamp_seconds')
[[ ${backup:-0} -gt 0 ]] || { echo 'backup timestamp metric missing; run backup-full' >&2; exit 1; }
critical=$(ssh_node "$CONTROL_IP" "curl -fsS http://127.0.0.1:$PROMETHEUS_PORT/api/v1/alerts" | jq '[.data.alerts[]|select(.state=="firing" and .labels.severity=="critical")]|length')
[[ $critical -eq 0 ]] || { echo "$critical unexplained critical alerts" >&2; exit 1; }
dashboards=$(ssh_node "$CONTROL_IP" "curl -fsS -u admin:'$(cat "$HA_RUNTIME/grafana-admin-password")' 'http://127.0.0.1:$GRAFANA_PORT/api/search?type=dash-db'")
[[ $(jq 'length' <<<"$dashboards") -ge 3 ]] || { echo 'Grafana dashboards not provisioned' >&2; exit 1; }
cat >"$OBS_RUNTIME/healthy.json" <<EOF
{"timestamp":"$(date -u +%FT%TZ)","targets_up":$expected,"primary_count":1,"replica_count":2,"etcd_healthy":3,"haproxy_writable":1,"backup_timestamp":$backup,"critical_alerts":0}
EOF
cat "$OBS_RUNTIME/healthy.json"
