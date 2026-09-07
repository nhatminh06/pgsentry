#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../backup/common.sh"

PROMETHEUS_VERSION=3.13.1
PROMETHEUS_SHA256=962b812371aff838d152b6ff2d56fdb7a6396f5542f48ebf73421b9721f0d103
ALERTMANAGER_VERSION=0.33.1
ALERTMANAGER_SHA256=93d802cba6a8d27239d747ce117df7648d326ab67394e32247540b030e9842ba
NODE_EXPORTER_VERSION=1.12.1
NODE_EXPORTER_SHA256=b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63
GRAFANA_VERSION=13.1.3
GRAFANA_SHA256=5969987920b0c3846f846c2a53f8ce8fa35453f8a15bd88e1dc3aeef5e931db3
PROMETHEUS_PORT=9090
ALERTMANAGER_PORT=9093
GRAFANA_PORT=3000

observability_load() {
  [[ ${1:-} == full ]] || { echo 'M10 canonical observability requires PROFILE=full' >&2; exit 2; }
  backup_load "$1"
  OBS_RUNTIME="$PGSENTRY_RUNTIME/results/m10"
  OBS_SECRETS="$PGSENTRY_RUNTIME/observability"
  mkdir -p "$OBS_RUNTIME" "$OBS_SECRETS"
  chmod 700 "$PGSENTRY_RUNTIME" "$PGSENTRY_RUNTIME/results" "$OBS_RUNTIME" "$OBS_SECRETS"
}

prom_query() {
  local query=$1 encoded
  encoded=$(jq -rn --arg q "$query" '$q|@uri')
  ssh_node "$CONTROL_IP" "curl -fsS 'http://127.0.0.1:$PROMETHEUS_PORT/api/v1/query?query=$encoded'" |
    jq -r '.data.result[0].value[1] // empty'
}

wait_metric() {
  local query=$1 expected=$2 value
  for _ in $(seq 1 40); do
    value=$(prom_query "$query" 2>/dev/null || true)
    [[ $value == "$expected" ]] && return
    sleep 3
  done
  echo "metric did not reach $query = $expected (last=${value:-missing})" >&2
  return 1
}

alert_state() {
  local name=$1
  ssh_node "$CONTROL_IP" "curl -fsS http://127.0.0.1:$PROMETHEUS_PORT/api/v1/alerts" |
    jq -r --arg n "$name" '[.data.alerts[] | select(.labels.alertname==$n and .state=="firing")]|length'
}

wait_alert() {
  local name=$1 wanted=$2 count
  for _ in $(seq 1 50); do
    count=$(alert_state "$name" 2>/dev/null || echo 0)
    if [[ $wanted == firing && $count -gt 0 ]] || [[ $wanted == resolved && $count -eq 0 ]]; then return; fi
    sleep 3
  done
  echo "alert $name did not become $wanted" >&2
  return 1
}

alertmanager_count() {
  local name=$1
  ssh_node "$CONTROL_IP" "curl -fsS 'http://127.0.0.1:$ALERTMANAGER_PORT/api/v2/alerts?active=true&silenced=false&inhibited=false'" |
    jq -r --arg n "$name" '[.[]|select(.labels.alertname==$n)]|length'
}

wait_alertmanager() {
  local name=$1 wanted=$2 count
  for _ in $(seq 1 40); do
    count=$(alertmanager_count "$name" 2>/dev/null || echo 0)
    if [[ $wanted == firing && $count -gt 0 ]] || [[ $wanted == resolved && $count -eq 0 ]]; then return; fi
    sleep 3
  done
  echo "Alertmanager alert $name did not become $wanted" >&2
  return 1
}

evidence_event() {
  local scenario=$1 phase=$2 metric=$3 value=$4 alert=$5
  jq -nc --arg scenario "$scenario" --arg phase "$phase" --arg metric "$metric" --arg value "$value" \
    --arg alert "$alert" --arg timestamp "$(date -u +%FT%TZ)" \
    '{scenario:$scenario,phase:$phase,metric:$metric,value:$value,alert:$alert,timestamp:$timestamp}' >>"$OBS_RUNTIME/alerts.jsonl"
}

prepare_monitor_etcd_cert() {
  local pki="$ETCD_RUNTIME/pki"
  [[ -s $pki/ca.key ]] || { echo 'etcd CA missing; run etcd-configure first' >&2; exit 1; }
  [[ -s $OBS_SECRETS/etcd-monitor.crt ]] && return
  umask 077
  openssl genrsa -out "$OBS_SECRETS/etcd-monitor.key" 2048 >/dev/null 2>&1
  openssl req -new -key "$OBS_SECRETS/etcd-monitor.key" -subj '/CN=pgsentry-m10-monitor' -out "$OBS_SECRETS/etcd-monitor.csr"
  printf 'extendedKeyUsage=clientAuth\n' >"$OBS_SECRETS/etcd-monitor.ext"
  openssl x509 -req -in "$OBS_SECRETS/etcd-monitor.csr" -CA "$pki/ca.crt" -CAkey "$pki/ca.key" -CAcreateserial -days 825 -sha256 -extfile "$OBS_SECRETS/etcd-monitor.ext" -out "$OBS_SECRETS/etcd-monitor.crt" >/dev/null 2>&1
}
