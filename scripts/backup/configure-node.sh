#!/usr/bin/env bash
set -euo pipefail
version=$1 control=$2 repo=$3 stanza=$4
if [[ $(dpkg-query -W -f='${Version}' pgbackrest 2>/dev/null || true) != "$version" ]]; then
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "pgbackrest=$version" nfs-common
fi
sudo mkdir -p "$repo"
grep -qF "$control:$repo $repo nfs4" /etc/fstab || printf '%s\n' "$control:$repo $repo nfs4 rw,hard,_netdev,nosuid,nodev 0 0" | sudo tee -a /etc/fstab >/dev/null
mountpoint -q "$repo" || sudo mount "$repo"
sudo install -d -o root -g postgres -m 0750 /etc/pgbackrest
sudo install -d -o postgres -g postgres -m 0750 /var/log/pgbackrest
sudo tee /etc/pgbackrest/pgbackrest.conf >/dev/null <<EOF
[global]
repo1-path=$repo
repo1-retention-full=2
repo1-retention-archive-type=full
start-fast=y
process-max=2
log-level-console=info
log-level-file=detail

[$stanza]
pg1-path=/var/lib/postgresql/16/patroni
EOF
sudo chown root:postgres /etc/pgbackrest/pgbackrest.conf
sudo chmod 0640 /etc/pgbackrest/pgbackrest.conf
sudo -u postgres test -r "$repo"
pgbackrest version
