#!/usr/bin/env bash
set -euo pipefail
version=$1 sha=$2 subnet=$3
archive="node_exporter-${version}.linux-amd64.tar.gz"
url="https://github.com/prometheus/node_exporter/releases/download/v${version}/${archive}"
if ! id node_exporter >/dev/null 2>&1; then sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter; fi
if [[ ! -x /usr/local/bin/node_exporter ]] || [[ $(/usr/local/bin/node_exporter --version 2>&1 | awk '/version/{print $3; exit}') != "$version" ]]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$url" -o "$tmp/$archive"
  echo "$sha  $tmp/$archive" | sha256sum -c -
  tar -xzf "$tmp/$archive" -C "$tmp"
  sudo install -m 0755 "$tmp/node_exporter-${version}.linux-amd64/node_exporter" /usr/local/bin/node_exporter
fi
sudo install -d -o node_exporter -g node_exporter -m 0755 /var/lib/node_exporter/textfile
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<'UNIT'
[Unit]
Description=PgSentry node exporter
After=network-online.target
[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter/textfile
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/node_exporter/textfile
[Install]
WantedBy=multi-user.target
UNIT
sudo ufw allow from "$subnet" to any port 9100 proto tcp comment 'pgsentry-m10-node-exporter' >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
