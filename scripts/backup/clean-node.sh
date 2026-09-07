#!/usr/bin/env bash
set -euo pipefail
root=$1 mode=$2 repo=$3
for name in latest pitr; do
  [[ $mode == all || $mode == restore || $mode == "$name" ]] || continue
  data="$root/$name"
  sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D "$data" -m fast stop 2>/dev/null || true
  sudo rm -rf "$data"
done
sudo rm -f /etc/pgbackrest/pgbackrest-restore.conf
if [[ $mode == all ]]; then
  sudo rm -rf "$repo"
  sudo sed -i '\|# pgsentry-m9 repository|d;\|/var/lib/pgbackrest .*pgsentry-m9|d' /etc/exports
  sudo exportfs -ra
fi
