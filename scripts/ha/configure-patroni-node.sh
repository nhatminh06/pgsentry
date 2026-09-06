#!/usr/bin/env bash
set -euo pipefail
name=$1 ip=$2 subnet=$3 scope=$4 namespace=$5 etcd_hosts=$6
IFS= read -r superpass; IFS= read -r replpass
data=/var/lib/postgresql/16/patroni
if sudo test -s "$data/PG_VERSION" && ! sudo test -f /etc/patroni/patroni.yml; then echo 'existing Patroni data lacks managed config; refusing destructive action' >&2; exit 1; fi
if ! sudo test -s "$data/PG_VERSION"; then
  if sudo test -d "$data" && [[ -n $(sudo find "$data" -mindepth 1 -maxdepth 1 -print -quit) ]]; then echo 'partial Patroni data directory found; refusing destructive recovery' >&2; exit 1; fi
  sudo install -d -o postgres -g postgres -m 700 "$data"
fi
config_tmp=$(mktemp)
cat >"$config_tmp" <<EOF
scope: $scope
namespace: $namespace
name: $name
restapi:
  listen: $ip:8008
  connect_address: $ip:8008
etcd3:
  hosts: $etcd_hosts
  protocol: https
  cacert: /etc/patroni/pki/ca.crt
  cert: /etc/patroni/pki/client.crt
  key: /etc/patroni/pki/client.key
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: 'on'
        wal_log_hints: 'on'
        max_wal_senders: 10
        max_replication_slots: 10
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host replication replicator $subnet scram-sha-256
    - host all all $subnet scram-sha-256
    - host all all 127.0.0.1/32 scram-sha-256
postgresql:
  listen: $ip:5432
  connect_address: $ip:5432
  data_dir: $data
  bin_dir: /usr/lib/postgresql/16/bin
  authentication:
    superuser:
      username: postgres
      password: $superpass
    replication:
      username: replicator
      password: $replpass
  parameters:
    unix_socket_directories: /var/run/postgresql
    password_encryption: scram-sha-256 # ggignore
  create_replica_methods:
    - basebackup
  basebackup:
    checkpoint: fast
  use_pg_rewind: true
  remove_data_directory_on_rewind_failure: false
  remove_data_directory_on_diverged_timelines: false
tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nostream: false
EOF
if ! sudo cmp -s "$config_tmp" /etc/patroni/patroni.yml; then sudo install -o root -g postgres -m 640 "$config_tmp" /etc/patroni/patroni.yml; fi
rm -f "$config_tmp"
sudo tee /etc/systemd/system/patroni.service >/dev/null <<'EOF'
[Unit]
Description=pgsentry Patroni PostgreSQL HA controller
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/opt/patroni/bin/patroni /etc/patroni/patroni.yml
Restart=on-failure
RestartSec=5s
KillMode=process
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
EOF
sudo ufw allow from "$subnet" to any port 5432 proto tcp comment 'pgsentry PostgreSQL' >/dev/null
sudo ufw allow from "$subnet" to any port 8008 proto tcp comment 'pgsentry Patroni REST' >/dev/null
sudo systemctl daemon-reload; sudo systemctl enable --now patroni
