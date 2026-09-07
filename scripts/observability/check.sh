#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; observability_load "${1:-}"
ssh_node "$CONTROL_IP" 'sudo /usr/local/bin/promtool check config /etc/prometheus/prometheus.yml; sudo /usr/local/bin/promtool check rules /etc/prometheus/rules.yml; sudo /usr/local/bin/amtool check-config /etc/alertmanager/alertmanager.yml; systemctl is-active --quiet prometheus alertmanager grafana-server node_exporter pgsentry-metrics.timer'
for ip in "${PG_IPS[@]}" "${ETCD_IPS[@]}"; do ssh_node "$ip" 'systemctl is-active --quiet node_exporter'; done
echo 'M10 services and rendered monitoring configuration are valid'
