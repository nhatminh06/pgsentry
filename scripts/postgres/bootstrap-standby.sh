#!/usr/bin/env bash
set -euo pipefail

primary=$1
slot=$2
force=${3:-no}
IFS= read -r replication_password
data=/var/lib/postgresql/16/main

if [[ $force != yes ]] && sudo -u postgres psql -Atqc 'SELECT pg_is_in_recovery()' 2>/dev/null | grep -qx t; then
  for attempt in $(seq 1 15); do
    sender=$(sudo -u postgres psql -Atqc "SELECT sender_host FROM pg_stat_wal_receiver" 2>/dev/null || true)
    if [[ $sender == "$primary" ]]; then
      echo "healthy standby already follows $primary; no rebuild needed"
      exit 0
    fi
    [[ -n $sender ]] && break
    sleep 2
  done
fi

sudo systemctl stop postgresql
sudo rm -rf "$data"
sudo install -d -o postgres -g postgres -m 700 "$data"
printf '%s:5432:*:replicator:%s\n' "$primary" "$replication_password" \
  | sudo tee /var/lib/postgresql/.pgpass >/dev/null
sudo chown postgres:postgres /var/lib/postgresql/.pgpass
sudo chmod 600 /var/lib/postgresql/.pgpass

sudo -u postgres pg_basebackup \
  --dbname="host=$primary user=replicator application_name=$slot" \
  --pgdata="$data" \
  --wal-method=stream \
  --write-recovery-conf \
  --slot="$slot" \
  --progress
sudo systemctl start postgresql
