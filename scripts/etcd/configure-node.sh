#!/usr/bin/env bash
set -euo pipefail
name=$1 ip=$2 cluster=$3 token=$4 subnet=$5
if [[ -d /var/lib/etcd/member ]] && [[ ! -f /etc/etcd/etcd.yml ]]; then
  echo 'existing etcd data found without managed configuration; refusing to reinitialize' >&2; exit 1
fi
sudo tee /etc/etcd/etcd.yml >/dev/null <<EOF
name: $name
data-dir: /var/lib/etcd
listen-peer-urls: https://$ip:2380
initial-advertise-peer-urls: https://$ip:2380
listen-client-urls: https://$ip:2379,https://127.0.0.1:2379
advertise-client-urls: https://$ip:2379
initial-cluster: $cluster
initial-cluster-state: new
initial-cluster-token: $token
client-transport-security:
  cert-file: /etc/etcd/pki/server.crt
  key-file: /etc/etcd/pki/server.key
  trusted-ca-file: /etc/etcd/pki/ca.crt
  client-cert-auth: true
peer-transport-security:
  cert-file: /etc/etcd/pki/peer.crt
  key-file: /etc/etcd/pki/peer.key
  trusted-ca-file: /etc/etcd/pki/ca.crt
  client-cert-auth: true
EOF
sudo chown root:etcd /etc/etcd/etcd.yml; sudo chmod 640 /etc/etcd/etcd.yml
sudo tee /etc/systemd/system/etcd.service >/dev/null <<'EOF'
[Unit]
Description=pgsentry etcd member
After=network-online.target
Wants=network-online.target
[Service]
User=etcd
Group=etcd
ExecStart=/usr/local/bin/etcd --config-file=/etc/etcd/etcd.yml
Restart=on-failure
RestartSec=5s
LimitNOFILE=40000
[Install]
WantedBy=multi-user.target
EOF
sudo ufw allow from "$subnet" to any port 2379 proto tcp comment 'pgsentry etcd client' >/dev/null
sudo ufw allow from "$subnet" to any port 2380 proto tcp comment 'pgsentry etcd peer' >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now etcd
