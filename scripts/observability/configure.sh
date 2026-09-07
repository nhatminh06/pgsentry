#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; observability_load "${1:-}"; prepare_monitor_etcd_cert
grafana_password=$(runtime_secret grafana-admin-password)
monitor_password=$(runtime_secret monitor-password)
leader=$(current_leader_ip)
sql "$leader" "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='pgsentry_monitor') THEN CREATE ROLE pgsentry_monitor LOGIN PASSWORD '$monitor_password'; END IF; END \$\$; ALTER ROLE pgsentry_monitor PASSWORD '$monitor_password'; GRANT pg_monitor TO pgsentry_monitor;" >/dev/null
for ip in "${PG_IPS[@]}"; do
  ssh_node "$ip" "sudo grep -q 'pgsentry_monitor' /etc/postgresql/16/main/pg_hba.conf || echo 'host all pgsentry_monitor $CONTROL_IP/32 scram-sha-256' | sudo tee -a /etc/postgresql/16/main/pg_hba.conf >/dev/null; sudo -u postgres psql -Atc 'select pg_reload_conf()' >/dev/null"
done
all_ips=("${PG_IPS[@]}" "${ETCD_IPS[@]}" "$CONTROL_IP")
for ip in "${all_ips[@]}"; do wait_for_ssh "$ip"; run_remote_script "$ip" "$PGSENTRY_ROOT/scripts/observability/install-node.sh" "$NODE_EXPORTER_VERSION" "$NODE_EXPORTER_SHA256" "$SUBNET"; done
ssh_node "$CONTROL_IP" 'sudo install -d -m 0750 /etc/prometheus/pki /etc/alertmanager /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards'
copy_remote "$CONTROL_IP" "$PGSENTRY_ROOT/monitoring/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml 0644
copy_remote "$CONTROL_IP" "$PGSENTRY_ROOT/monitoring/prometheus/rules.yml" /etc/prometheus/rules.yml 0644
copy_remote "$CONTROL_IP" "$PGSENTRY_ROOT/monitoring/alertmanager/alertmanager.yml" /etc/alertmanager/alertmanager.yml 0644
copy_remote "$CONTROL_IP" "$ETCD_RUNTIME/pki/ca.crt" /etc/prometheus/pki/etcd-ca.crt 0644
copy_remote "$CONTROL_IP" "$OBS_SECRETS/etcd-monitor.crt" /etc/prometheus/pki/etcd-monitor.crt 0644
copy_remote "$CONTROL_IP" "$OBS_SECRETS/etcd-monitor.key" /etc/prometheus/pki/etcd-monitor.key 0600
copy_remote "$CONTROL_IP" "$PGSENTRY_ROOT/scripts/observability/collector.sh" /usr/local/sbin/pgsentry-metrics 0755
for f in "$PGSENTRY_ROOT"/monitoring/grafana/dashboards/*.json; do copy_remote "$CONTROL_IP" "$f" "/var/lib/grafana/dashboards/$(basename "$f")" 0644; done
copy_remote "$CONTROL_IP" "$PGSENTRY_ROOT/monitoring/grafana/provisioning/datasources/prometheus.yml" /etc/grafana/provisioning/datasources/pgsentry.yml 0644
copy_remote "$CONTROL_IP" "$PGSENTRY_ROOT/monitoring/grafana/provisioning/dashboards/pgsentry.yml" /etc/grafana/provisioning/dashboards/pgsentry.yml 0644
printf '%s\n%s\n' "$grafana_password" "$monitor_password" | run_remote_script_with_input "$CONTROL_IP" "$PGSENTRY_ROOT/scripts/observability/configure-control.sh" "$PROMETHEUS_VERSION" "$PROMETHEUS_SHA256" "$ALERTMANAGER_VERSION" "$ALERTMANAGER_SHA256" "$GRAFANA_VERSION" "$GRAFANA_SHA256" "$SUBNET" "'$grafana_password'" "'$monitor_password'"
ssh_node "$CONTROL_IP" 'sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus; sudo chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager; sudo chown -R grafana:grafana /var/lib/grafana/dashboards; sudo systemctl restart alertmanager prometheus grafana-server pgsentry-metrics.timer; sudo systemctl start pgsentry-metrics.service'
echo "Grafana=http://$CONTROL_IP:$GRAFANA_PORT user=admin password=$HA_RUNTIME/grafana-admin-password"
