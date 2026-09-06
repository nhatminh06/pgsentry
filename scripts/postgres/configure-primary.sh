#!/usr/bin/env bash
set -euo pipefail

subnet=$1
IFS= read -r replication_password

[[ $replication_password =~ ^[0-9a-f]{64}$ ]]
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
SELECT format('CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', '$replication_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') \gexec
SELECT format('ALTER ROLE replicator WITH REPLICATION LOGIN PASSWORD %L', '$replication_password') \gexec
ALTER SYSTEM SET listen_addresses = '*';
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = '10';
ALTER SYSTEM SET max_replication_slots = '10';
ALTER SYSTEM SET hot_standby = 'on';
SQL

hba=/etc/postgresql/16/main/pg_hba.conf
sudo sed -i '/# pgsentry-m2 replication/,+1d' "$hba"
printf '%s\n%s\n' \
  '# pgsentry-m2 replication' \
  "host replication replicator $subnet scram-sha-256" \
  | sudo tee -a "$hba" >/dev/null
sudo systemctl restart postgresql
sudo -u postgres pg_isready
