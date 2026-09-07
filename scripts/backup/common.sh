#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../ha/common.sh"

PGBACKREST_VERSION=2.50-1build2
BACKUP_STANZA=pgsentry
BACKUP_REPO=/var/lib/pgbackrest
RESTORE_ROOT=/var/lib/pgbackrest-restore
RESTORE_PORT=55432

backup_load() {
  local profile=${1:-}
  [[ $profile == full ]] || { echo 'M9 canonical backup/PITR requires PROFILE=full' >&2; exit 2; }
  load_profile "$profile"
  BACKUP_RUNTIME="$PGSENTRY_RUNTIME/results/m9"
  mkdir -p "$BACKUP_RUNTIME"
  chmod 700 "$PGSENTRY_RUNTIME" "$PGSENTRY_RUNTIME/results" "$BACKUP_RUNTIME"
}

current_leader() { leader_name; }
current_leader_ip() { name_ip "$(current_leader)"; }
state_file() { echo "$BACKUP_RUNTIME/state.env"; }

write_state() {
  local key=$1 value=$2 file; file=$(state_file)
  touch "$file"; chmod 600 "$file"
  sed -i "/^${key}=/d" "$file"
  printf '%s=%q\n' "$key" "$value" >>"$file"
}

load_state() {
  local file; file=$(state_file)
  [[ -s $file ]] || { echo "M9 state missing: $file" >&2; exit 1; }
  # shellcheck disable=SC1090
  source "$file"
}

control_pgbackrest() { ssh_node "$CONTROL_IP" "sudo -u postgres pgbackrest --stanza=$BACKUP_STANZA $*"; }
leader_pgbackrest() { local ip; ip=$(current_leader_ip); ssh_node "$ip" "sudo -u postgres pgbackrest --stanza=$BACKUP_STANZA $*"; }

wait_replica_value() {
  local ip=$1 marker=$2 expected=$3 got
  for _ in $(seq 1 30); do
    got=$(sql "$ip" "SELECT count(*) FROM m9_recovery.markers WHERE marker='$marker'" 2>/dev/null || true)
    [[ $got == "$expected" ]] && return
    sleep 1
  done
  echo "marker $marker did not reach expected count $expected on $ip" >&2
  return 1
}

force_archive() {
  local ip before switched after
  ip=$(current_leader_ip)
  before=$(sql "$ip" 'SELECT archived_count FROM pg_stat_archiver')
  sql "$ip" "SELECT pg_logical_emit_message(true,'pgsentry-m9-archive',clock_timestamp()::text)" >/dev/null
  switched=$(sql "$ip" 'SELECT pg_walfile_name(pg_switch_wal())')
  for _ in $(seq 1 60); do
    after=$(sql "$ip" 'SELECT archived_count FROM pg_stat_archiver')
    [[ $after -gt $before ]] && break
    sleep 2
  done
  [[ ${after:-0} -gt $before ]] || { sql "$ip" "SELECT row_to_json(s) FROM pg_stat_archiver s"; return 1; }
  write_state ARCHIVED_WAL "$switched"
  printf '%s\n' "$switched"
}
