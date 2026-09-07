#!/usr/bin/env bash
set -euo pipefail
version=$1 subnet=$2 repo=$3 restore_root=$4 stanza=$5
if [[ $(dpkg-query -W -f='${Version}' pgbackrest 2>/dev/null || true) != "$version" ]]; then
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "pgbackrest=$version" nfs-kernel-server postgresql-16
fi
sudo systemctl disable --now postgresql.service postgresql@16-main.service 2>/dev/null || true
sudo install -d -o postgres -g postgres -m 0750 "$repo"
sudo install -d -o postgres -g postgres -m 0700 "$restore_root"
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
pg1-path=$restore_root/latest
EOF
sudo chown root:postgres /etc/pgbackrest/pgbackrest.conf
sudo chmod 0640 /etc/pgbackrest/pgbackrest.conf
sudo touch /etc/exports
sudo sed -i '\|# pgsentry-m9 repository|d;\|/var/lib/pgbackrest .*pgsentry-m9|d' /etc/exports
postgres_uid=$(id -u postgres); postgres_gid=$(id -g postgres)
printf '%s %s(rw,sync,no_subtree_check,all_squash,anonuid=%s,anongid=%s) # pgsentry-m9 repository\n' "$repo" "$subnet" "$postgres_uid" "$postgres_gid" | sudo tee -a /etc/exports >/dev/null
sudo exportfs -ra
sudo systemctl enable --now nfs-server
stat -c 'repository=%n owner=%U group=%G mode=%a' "$repo"
pgbackrest version
