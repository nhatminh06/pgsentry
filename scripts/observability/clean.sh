#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; observability_load "${1:-}"
for ip in "${PG_IPS[@]}" "${ETCD_IPS[@]}" "$CONTROL_IP"; do
  ssh_node "$ip" "sudo systemctl disable --now node_exporter 2>/dev/null || true; sudo rm -f /etc/systemd/system/node_exporter.service /usr/local/bin/node_exporter; sudo rm -rf /var/lib/node_exporter; sudo ufw --force delete allow from '$SUBNET' to any port 9100 proto tcp >/dev/null 2>&1 || true" || true
done
ssh_node "$CONTROL_IP" "sudo systemctl disable --now prometheus alertmanager grafana-server pgsentry-metrics.timer 2>/dev/null || true; sudo rm -f /etc/systemd/system/prometheus.service /etc/systemd/system/alertmanager.service /etc/systemd/system/pgsentry-metrics.service /etc/systemd/system/pgsentry-metrics.timer /etc/pgsentry-monitor.env /usr/local/bin/prometheus /usr/local/bin/promtool /usr/local/bin/alertmanager /usr/local/bin/amtool /usr/local/sbin/pgsentry-metrics; sudo rm -rf /etc/prometheus /etc/alertmanager /etc/grafana /var/lib/prometheus /var/lib/alertmanager /var/lib/grafana /var/log/grafana; sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq grafana >/dev/null 2>&1 || true; sudo ufw --force delete allow from '$SUBNET' to any port 3000 proto tcp >/dev/null 2>&1 || true; sudo systemctl daemon-reload" || true
leader=$(current_leader_ip 2>/dev/null || true); [[ -n $leader ]] && sql "$leader" 'DROP ROLE IF EXISTS pgsentry_monitor' >/dev/null || true
[[ -n ${leader:-} ]] && sql "$leader" 'DROP TABLE IF EXISTS public.m10_lag' >/dev/null || true
rm -rf "$OBS_SECRETS" "$OBS_RUNTIME" "$HA_RUNTIME/grafana-admin-password" "$HA_RUNTIME/monitor-password"
echo 'M10 monitoring services, state, credentials, and evidence removed'
