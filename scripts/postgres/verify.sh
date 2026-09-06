#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
load_profile "${1:-}"

wait_for_query "$PG_PRIMARY" 'SELECT pg_is_in_recovery()' f
wait_for_query "$PG_STANDBY_ONE" 'SELECT pg_is_in_recovery()' t
wait_for_query "$PG_STANDBY_TWO" 'SELECT pg_is_in_recovery()' t
wait_for_query "$PG_PRIMARY" "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming' AND sync_state = 'async'" 2

value="m2-initial-$(date -u +%Y%m%dT%H%M%SZ)"
ssh_node "$PG_PRIMARY" "sudo -u postgres psql -v ON_ERROR_STOP=1 -c 'CREATE TABLE IF NOT EXISTS public.m2_evidence (value text PRIMARY KEY, created_at timestamptz DEFAULT now())' -c \"INSERT INTO public.m2_evidence(value) VALUES ('$value')\""
wait_for_query "$PG_STANDBY_ONE" "SELECT value FROM public.m2_evidence WHERE value = '$value'" "$value"
wait_for_query "$PG_STANDBY_TWO" "SELECT value FROM public.m2_evidence WHERE value = '$value'" "$value"

if ssh_node "$PG_STANDBY_ONE" "sudo -u postgres psql -v ON_ERROR_STOP=1 -c \"INSERT INTO public.m2_evidence(value) VALUES ('standby-write-must-fail')\"" >"$PGSENTRY_RUNTIME/standby-write.out" 2>&1; then
  echo "standby unexpectedly accepted a write" >&2
  exit 1
fi
grep -Eq 'read-only transaction|cannot execute INSERT during recovery' "$PGSENTRY_RUNTIME/standby-write.out"

for address in "$PG_PRIMARY" "$PG_STANDBY_ONE" "$PG_STANDBY_TWO"; do
  ssh_node "$address" 'sudo systemctl restart postgresql'
done
wait_for_query "$PG_PRIMARY" "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'" 2
wait_for_query "$PG_STANDBY_ONE" "SELECT value FROM public.m2_evidence WHERE value = '$value'" "$value"
wait_for_query "$PG_STANDBY_TWO" "SELECT value FROM public.m2_evidence WHERE value = '$value'" "$value"

echo "primary_role=$(ssh_node "$PG_PRIMARY" "sudo -u postgres psql -Atqc 'SELECT pg_is_in_recovery()'")"
ssh_node "$PG_PRIMARY" "sudo -u postgres psql -P pager=off -c \"SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication ORDER BY application_name\""
echo "replicated_value=$value"
echo "standby write rejected with: $(tail -1 "$PGSENTRY_RUNTIME/standby-write.out")"
echo "restart/reconnect verification passed"
