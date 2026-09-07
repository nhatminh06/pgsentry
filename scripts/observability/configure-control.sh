#!/usr/bin/env bash
set -euo pipefail
prom_version=$1 prom_sha=$2 am_version=$3 am_sha=$4 grafana_version=$5 grafana_sha=$6 subnet=$7 grafana_password=$8 monitor_password=$9
install_archive() {
  local component=$1 version=$2 sha=$3 binary=$4
  local archive="${component}-${version}.linux-amd64.tar.gz" tmp url
  url="https://github.com/prometheus/${component}/releases/download/v${version}/${archive}"
  tmp=$(mktemp -d); curl -fsSL "$url" -o "$tmp/$archive"; echo "$sha  $tmp/$archive" | sha256sum -c -
  tar -xzf "$tmp/$archive" -C "$tmp"; sudo install -m 0755 "$tmp/${component}-${version}.linux-amd64/$binary" "/usr/local/bin/$binary"; rm -rf "$tmp"
}
id prometheus >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus
id alertmanager >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin alertmanager
install_archive prometheus "$prom_version" "$prom_sha" prometheus
tmp=$(mktemp -d); curl -fsSL "https://github.com/prometheus/prometheus/releases/download/v${prom_version}/prometheus-${prom_version}.linux-amd64.tar.gz" -o "$tmp/prometheus.tar.gz"; echo "$prom_sha  $tmp/prometheus.tar.gz" | sha256sum -c -; tar -xzf "$tmp/prometheus.tar.gz" -C "$tmp"; sudo install -m 0755 "$tmp/prometheus-${prom_version}.linux-amd64/promtool" /usr/local/bin/promtool; rm -rf "$tmp"
install_archive alertmanager "$am_version" "$am_sha" alertmanager
tmp=$(mktemp -d); curl -fsSL "https://github.com/prometheus/alertmanager/releases/download/v${am_version}/alertmanager-${am_version}.linux-amd64.tar.gz" -o "$tmp/alertmanager.tar.gz"; echo "$am_sha  $tmp/alertmanager.tar.gz" | sha256sum -c -; tar -xzf "$tmp/alertmanager.tar.gz" -C "$tmp"; sudo install -m 0755 "$tmp/alertmanager-${am_version}.linux-amd64/amtool" /usr/local/bin/amtool; rm -rf "$tmp"
sudo apt-get update -qq
sudo apt-get install -y -qq jq postgresql-client curl >/dev/null
if ! dpkg-query -W -f='${Version}' grafana 2>/dev/null | grep -q "^${grafana_version}"; then
  tmp=$(mktemp); curl -fsSL "https://dl.grafana.com/oss/release/grafana_${grafana_version}_amd64.deb" -o "$tmp"; echo "$grafana_sha  $tmp" | sha256sum -c -; sudo dpkg -i "$tmp" >/dev/null || sudo apt-get -f install -y -qq; rm -f "$tmp"
fi
sudo install -d -o prometheus -g prometheus -m 0750 /etc/prometheus /var/lib/prometheus /etc/prometheus/pki
sudo install -d -o alertmanager -g alertmanager -m 0750 /etc/alertmanager /var/lib/alertmanager
sudo install -d -o grafana -g grafana -m 0750 /var/lib/grafana/dashboards
sudo tee /etc/pgsentry-monitor.env >/dev/null <<EOF
PGPASSWORD='$monitor_password'
EOF
sudo chmod 0600 /etc/pgsentry-monitor.env
sudo sed -i "s/^;http_addr =.*/http_addr = 0.0.0.0/; s/^;admin_password =.*/admin_password = $grafana_password/; s/^;disable_initial_admin_creation =.*/disable_initial_admin_creation = false/" /etc/grafana/grafana.ini
sudo tee /etc/systemd/system/prometheus.service >/dev/null <<'UNIT'
[Unit]
Description=PgSentry Prometheus
After=network-online.target alertmanager.service
[Service]
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --storage.tsdb.retention.time=7d --web.listen-address=127.0.0.1:9090
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
sudo tee /etc/systemd/system/alertmanager.service >/dev/null <<'UNIT'
[Unit]
Description=PgSentry Alertmanager
After=network-online.target
[Service]
User=alertmanager
Group=alertmanager
ExecStart=/usr/local/bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --storage.path=/var/lib/alertmanager --web.listen-address=127.0.0.1:9093
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
sudo tee /etc/systemd/system/pgsentry-metrics.service >/dev/null <<'UNIT'
[Unit]
Description=Collect PgSentry semantic metrics
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pgsentry-metrics
UNIT
sudo tee /etc/systemd/system/pgsentry-metrics.timer >/dev/null <<'UNIT'
[Unit]
Description=Collect PgSentry semantic metrics every 15 seconds
[Timer]
OnBootSec=10s
OnUnitActiveSec=15s
AccuracySec=1s
[Install]
WantedBy=timers.target
UNIT
sudo ufw allow from "$subnet" to any port 3000 proto tcp comment 'pgsentry-m10-grafana' >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now alertmanager prometheus grafana-server pgsentry-metrics.timer
sudo systemctl start pgsentry-metrics.service
