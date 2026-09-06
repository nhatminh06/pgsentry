#!/usr/bin/env bash
set -euo pipefail
subnet=$1; shift
sudo env DEBIAN_FRONTEND=noninteractive apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y haproxy postgresql-client-16 socat
sudo tee /etc/haproxy/haproxy.cfg >/dev/null <<EOF
global
  log /dev/log local0
  stats socket /run/haproxy/admin.sock mode 660 level admin
  user haproxy
  group haproxy
defaults
  log global
  mode tcp
  timeout connect 5s
  timeout client 30s
  timeout server 30s
frontend postgres_write
  bind *:5000
  default_backend patroni_primary
backend patroni_primary
  option httpchk GET /primary
  http-check expect status 200
EOF
while [[ $# -gt 1 ]]; do echo "  server $1 $2:5432 check port 8008 inter 2s fall 2 rise 2" | sudo tee -a /etc/haproxy/haproxy.cfg >/dev/null; shift 2; done
sudo ufw allow from "$subnet" to any port 5000 proto tcp comment 'pgsentry HAProxy PostgreSQL' >/dev/null
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl enable --now haproxy; sudo systemctl reload haproxy
