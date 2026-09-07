#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../durability/common.sh"
profile=${1:-full}; durability_load "$profile"; [[ $profile == full ]]
runtime="$PGSENTRY_RUNTIME/results/m8"; mkdir -p "$runtime"; chmod 700 "$runtime"
result="$runtime/runtime.json"; password=$(runtime_secret superuser-password); leader=$(leader_name); leader_ip=$(name_ip "$leader")
remote_app() { local host=$1 app=$2 query=$3 encoded; encoded=$(printf %s "$query"|base64 -w0); ssh_node "$host" "printf %s '$encoded'|base64 -d|PGPASSWORD='$password' PGAPPNAME='$app' psql -h '$host' -U postgres -d postgres -v ON_ERROR_STOP=1 -Atq"; }
remote_sql() { remote_app "$1" pgsafe-m8-control "$2"; }
haproxy_sql() { local query=$1 encoded; encoded=$(printf %s "$query"|base64 -w0); ssh_node "$CONTROL_IP" "printf %s '$encoded'|base64 -d|PGPASSWORD='$password' PGAPPNAME=pgsafe-m8-workload psql -h 127.0.0.1 -p '$HAPROXY_WRITE_PORT' -U postgres -d postgres -v ON_ERROR_STOP=1 -Atq"; }
cleanup() { set +e; remote_sql "$leader_ip" "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name LIKE 'pgsafe-m8%' AND pid<>pg_backend_pid(); DROP SCHEMA IF EXISTS pgsafe_m8 CASCADE;" >/dev/null; }
trap cleanup EXIT INT TERM
"$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" async --quiet
cleanup
remote_sql "$leader_ip" "CREATE SCHEMA pgsafe_m8; CREATE TABLE pgsafe_m8.items(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, value integer NOT NULL, marker text); INSERT INTO pgsafe_m8.items(value) SELECT g FROM generate_series(1,20000) g;"

# Plain CREATE INDEX waits behind a writer's RowExclusiveLock, then lock_timeout bounds the wait.
remote_app "$leader_ip" pgsafe-m8-index-blocker "BEGIN; UPDATE pgsafe_m8.items SET marker='block' WHERE id=1; SELECT pg_sleep(8); ROLLBACK;" >/dev/null & blocker=$!
sleep 1; start=$(date +%s%3N); plain_output_file="$runtime/plain-index.stderr"; set +e
remote_app "$leader_ip" pgsafe-m8-plain-index "SET lock_timeout='2s'; SET statement_timeout='6s'; CREATE INDEX items_value_plain ON pgsafe_m8.items(value);" >"$plain_output_file" 2>&1 & migration=$!
set -e; sleep .5
plain_lock=$(remote_sql "$leader_ip" "SELECT mode FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='pgsafe-m8-plain-index' AND NOT l.granted ORDER BY mode LIMIT 1")
[[ -n $plain_lock ]]; set +e
plain_client_output=$(haproxy_sql "SET lock_timeout='700ms'; SET statement_timeout='3s'; INSERT INTO pgsafe_m8.items(value,marker) VALUES (2,'queued-behind-index');" 2>&1); plain_client_rc=$?
wait "$migration"; plain_rc=$?; set -e; plain_ms=$(( $(date +%s%3N)-start )); wait "$blocker"
plain_output=$(<"$plain_output_file"); [[ $plain_rc -ne 0 && $plain_output == *"lock timeout"* ]]
[[ $plain_client_rc -ne 0 && $plain_client_output == *"lock timeout"* ]]

# CREATE INDEX CONCURRENTLY runs while application-style writes use HAProxy.
for _ in $(seq 1 25); do haproxy_sql "INSERT INTO pgsafe_m8.items(value,marker) VALUES (1,'live');" >/dev/null; sleep .05; done & writer=$!
start=$(date +%s%3N); remote_sql "$leader_ip" "SET lock_timeout='2s'; SET statement_timeout='30s'; CREATE INDEX CONCURRENTLY items_value_concurrent ON pgsafe_m8.items(value);"; concurrent_ms=$(( $(date +%s%3N)-start )); wait "$writer"
concurrent_valid=$(remote_sql "$leader_ip" "SELECT indisvalid FROM pg_index WHERE indexrelid='pgsafe_m8.items_value_concurrent'::regclass")

# A strong ALTER waits for AccessExclusiveLock and fails at the bounded lock boundary.
remote_app "$leader_ip" pgsafe-m8-alter-blocker "BEGIN; SELECT count(*) FROM pgsafe_m8.items; SELECT pg_sleep(8); COMMIT;" >/dev/null & blocker=$!
sleep 1; start=$(date +%s%3N); alter_output_file="$runtime/alter-table.stderr"; set +e
remote_app "$leader_ip" pgsafe-m8-alter-table "SET lock_timeout='2s'; SET statement_timeout='6s'; ALTER TABLE pgsafe_m8.items ADD COLUMN note text;" >"$alter_output_file" 2>&1 & migration=$!
set -e; sleep .5
alter_lock=$(remote_sql "$leader_ip" "SELECT mode FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='pgsafe-m8-alter-table' AND NOT l.granted ORDER BY mode LIMIT 1")
[[ -n $alter_lock ]]; set +e; wait "$migration"; alter_rc=$?; set -e; alter_ms=$(( $(date +%s%3N)-start )); wait "$blocker"
alter_output=$(<"$alter_output_file"); [[ $alter_rc -ne 0 && $alter_output == *"lock timeout"* ]]

# Staged constraint records the unvalidated and validated catalog states.
remote_sql "$leader_ip" "SET lock_timeout='2s'; ALTER TABLE pgsafe_m8.items ADD CONSTRAINT items_value_positive CHECK(value>0) NOT VALID;"
before_valid=$(remote_sql "$leader_ip" "SELECT convalidated FROM pg_constraint WHERE conname='items_value_positive'")
start=$(date +%s%3N); remote_sql "$leader_ip" "SET lock_timeout='2s'; SET statement_timeout='30s'; ALTER TABLE pgsafe_m8.items VALIDATE CONSTRAINT items_value_positive;"; validate_ms=$(( $(date +%s%3N)-start ))
after_valid=$(remote_sql "$leader_ip" "SELECT convalidated FROM pg_constraint WHERE conname='items_value_positive'")
[[ $before_valid == f && $after_valid == t ]]

# Harmless committed DDL is physically reproduced on both replicas.
remote_sql "$leader_ip" "CREATE TABLE pgsafe_m8.replication_marker(id integer PRIMARY KEY); CREATE INDEX replication_marker_id ON pgsafe_m8.replication_marker(id);"
replicated=(); for ip in "${PG_IPS[@]}"; do for _ in $(seq 1 30); do seen=$(remote_sql "$ip" "SELECT to_regclass('pgsafe_m8.replication_marker') IS NOT NULL" 2>/dev/null||echo f); [[ $seen == t ]]&&break;sleep 1;done;[[ $seen == t ]];replicated+=("$ip");done
blocked=$(remote_sql "$leader_ip" "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'pgsafe-m8%' AND wait_event_type='Lock'")
[[ $blocked -eq 0 ]]
jq -n --arg profile "$profile" --arg pg "$(remote_sql "$leader_ip" 'SHOW server_version')" --arg leader "$leader" --arg plain_lock "$plain_lock" --arg alter_lock "$alter_lock" --argjson plain_ms "$plain_ms" --argjson concurrent_ms "$concurrent_ms" --arg valid "$concurrent_valid" --argjson alter_ms "$alter_ms" --argjson validate_ms "$validate_ms" --arg before "$before_valid" --arg after "$after_valid" --argjson blocked "$blocked" --argjson replicas "$(printf '%s\n' "${replicated[@]}"|jq -R .|jq -s .)" '{profile:$profile,postgresql:$pg,leader:$leader,plain_index:{result:"lock_timeout",waiting_observed:true,observed_ungranted_lock:$plain_lock,duration_ms:$plain_ms,queued_haproxy_write_result:"lock_timeout"},concurrent_index:{result:"created",valid:($valid=="t"),duration_ms:$concurrent_ms,workload_path:"control-01:5000",successful_writes:25},alter_table:{result:"lock_timeout",waiting_observed:true,observed_ungranted_lock:$alter_lock,duration_ms:$alter_ms},staged_constraint:{not_valid_catalog:$before,validated_catalog:$after,duration_ms:$validate_ms},replication:{observed_nodes:$replicas},remaining_blocked_sessions:$blocked,cleanup:"pending trap"}' | tee "$result"
cleanup; trap - EXIT INT TERM
"$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" async --quiet
echo "migration_runtime=passed evidence=$result"
