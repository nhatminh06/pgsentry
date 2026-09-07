#!/usr/bin/env bash
set -euo pipefail
mode=$1 repo=$2 root=$3 port=$4 stanza=$5 target=${6:-}
data="$root/$mode"
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D "$data" -m fast stop 2>/dev/null || true
sudo rm -rf "$data"
sudo install -d -o postgres -g postgres -m 0700 "$data"
config=$(mktemp)
cat >"$config" <<EOF
[global]
repo1-path=$repo
log-level-console=info
log-level-file=detail

[$stanza]
pg1-path=$data
EOF
sudo install -o root -g postgres -m 0640 "$config" /etc/pgbackrest/pgbackrest-restore.conf
rm -f "$config"
args=(--config=/etc/pgbackrest/pgbackrest-restore.conf --stanza="$stanza" --pg1-path="$data" --target-timeline=current)
if [[ $mode == pitr ]]; then
  [[ -n $target ]]
  args+=(--type=name --target="$target" --target-action=promote)
else
  args+=(--type=default)
fi
start=$(date +%s%3N)
sudo -u postgres pgbackrest "${args[@]}" restore
cat <<EOF | sudo tee -a "$data/postgresql.auto.conf" >/dev/null
listen_addresses = '127.0.0.1'
port = $port
unix_socket_directories = '/var/run/postgresql'
hot_standby = 'on'
EOF
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D "$data" -l "$data/restore.log" -o "-c listen_addresses=127.0.0.1 -p $port -c unix_socket_directories=/var/run/postgresql -c hba_file=$data/pg_hba.conf -c ident_file=$data/pg_ident.conf -c archive_mode=off -c archive_command=/bin/true" start
for _ in $(seq 1 90); do
  if sudo -u postgres psql -p "$port" -Atqc 'SELECT 1' 2>/dev/null | grep -qx 1; then break; fi
  sleep 2
done
sudo -u postgres psql -p "$port" -Atqc 'SELECT 1' | grep -qx 1
duration=$(( $(date +%s%3N)-start ))
printf 'mode=%s duration_ms=%s data=%s endpoint=127.0.0.1:%s\n' "$mode" "$duration" "$data" "$port"
