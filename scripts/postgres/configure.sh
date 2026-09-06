#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
load_profile "${1:-}"

for address in "$PG_PRIMARY" "$PG_STANDBY_ONE" "$PG_STANDBY_TWO"; do
  wait_for_ssh "$address"
  run_remote_script "$address" "$PGSENTRY_ROOT/scripts/postgres/install-node.sh"
done

password=$(runtime_password)
printf '%s\n' "$password" | run_remote_script_with_input "$PG_PRIMARY" \
  "$PGSENTRY_ROOT/scripts/postgres/configure-primary.sh" "$PG_SUBNET"
run_query "$PG_PRIMARY" "SELECT pg_create_physical_replication_slot('pg_02') WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'pg_02')"
run_query "$PG_PRIMARY" "SELECT pg_create_physical_replication_slot('pg_03') WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'pg_03')"

printf '%s\n' "$password" | run_remote_script_with_input "$PG_STANDBY_ONE" \
  "$PGSENTRY_ROOT/scripts/postgres/bootstrap-standby.sh" "$PG_PRIMARY" pg_02
printf '%s\n' "$password" | run_remote_script_with_input "$PG_STANDBY_TWO" \
  "$PGSENTRY_ROOT/scripts/postgres/bootstrap-standby.sh" "$PG_PRIMARY" pg_03

wait_for_query "$PG_STANDBY_ONE" 'SELECT pg_is_in_recovery()' t
wait_for_query "$PG_STANDBY_TWO" 'SELECT pg_is_in_recovery()' t
wait_for_query "$PG_PRIMARY" "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'" 2
echo "PostgreSQL 16 configured: primary=$PG_PRIMARY standbys=$PG_STANDBY_ONE,$PG_STANDBY_TWO"
