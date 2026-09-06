#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
load_profile "${1:-}"

old_role=$(run_query "$PG_PRIMARY" 'SELECT pg_is_in_recovery()' 2>/dev/null || true)
new_role=$(run_query "$PG_STANDBY_ONE" 'SELECT pg_is_in_recovery()' 2>/dev/null || true)
pre_value="already-proven-before-resume"
if [[ $old_role == f && $new_role == t ]]; then
  "$PGSENTRY_ROOT/scripts/postgres/verify.sh" "$1"
  pre_value="m2-pre-failover-$(date -u +%Y%m%dT%H%M%SZ)"
  ssh_node "$PG_PRIMARY" "sudo -u postgres psql -v ON_ERROR_STOP=1 -c \"INSERT INTO public.m2_evidence(value) VALUES ('$pre_value')\""
  wait_for_query "$PG_STANDBY_ONE" "SELECT value FROM public.m2_evidence WHERE value = '$pre_value'" "$pre_value"
  wait_for_query "$PG_STANDBY_TWO" "SELECT value FROM public.m2_evidence WHERE value = '$pre_value'" "$pre_value"

  ssh_node "$PG_PRIMARY" 'sudo systemctl disable --now postgresql; sudo systemctl mask --force postgresql postgresql@16-main.service'
  if ssh_node "$PG_PRIMARY" 'sudo -u postgres pg_isready' >/dev/null 2>&1; then
    echo "old primary is still available" >&2
    exit 1
  fi

  ssh_node "$PG_STANDBY_ONE" 'sudo -u postgres pg_ctlcluster 16 main promote'
  wait_for_query "$PG_STANDBY_ONE" 'SELECT pg_is_in_recovery()' f
elif [[ -z $old_role && $new_role == f ]]; then
  echo "resuming after pg-02 promotion; pg-01 is unavailable"
else
  echo "cluster roles are not a supported pre-failover or resumable state" >&2
  exit 1
fi

password=$(runtime_password)
printf '%s\n' "$password" | run_remote_script_with_input "$PG_STANDBY_ONE" \
  "$PGSENTRY_ROOT/scripts/postgres/configure-primary.sh" "$PG_SUBNET"
run_query "$PG_STANDBY_ONE" "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name = 'pg_03'"
run_query "$PG_STANDBY_ONE" "SELECT pg_create_physical_replication_slot('pg_03_from_pg_02') WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'pg_03_from_pg_02')"
printf '%s\n' "$password" | run_remote_script_with_input "$PG_STANDBY_TWO" \
  "$PGSENTRY_ROOT/scripts/postgres/bootstrap-standby.sh" "$PG_STANDBY_ONE" pg_03_from_pg_02 yes
wait_for_query "$PG_STANDBY_TWO" 'SELECT pg_is_in_recovery()' t
wait_for_query "$PG_STANDBY_ONE" "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'" 1

post_value="m2-post-failover-$(date -u +%Y%m%dT%H%M%SZ)"
ssh_node "$PG_STANDBY_ONE" "sudo -u postgres psql -v ON_ERROR_STOP=1 -c \"INSERT INTO public.m2_evidence(value) VALUES ('$post_value')\""
wait_for_query "$PG_STANDBY_TWO" "SELECT value FROM public.m2_evidence WHERE value = '$post_value'" "$post_value"

echo "old_primary_available=false"
echo "new_primary_recovery=$(ssh_node "$PG_STANDBY_ONE" "sudo -u postgres psql -Atqc 'SELECT pg_is_in_recovery()'")"
ssh_node "$PG_STANDBY_ONE" "sudo -u postgres psql -P pager=off -c \"SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication\""
echo "pre_failover_value=$pre_value"
echo "post_failover_value=$post_value"
echo "pg-03 follows the promoted pg-02; pg-01 remains stopped and masked"
