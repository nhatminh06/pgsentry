#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; profile=${1:-}; backup_load "$profile"
trap '"$PGSENTRY_ROOT/scripts/backup/clean.sh" "$profile" restore >/dev/null 2>&1 || true' EXIT INT TERM
"$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" async --quiet
"$PGSENTRY_ROOT/scripts/backup/check.sh" "$profile"
run="$(date -u +%Y%m%dT%H%M%SZ)-$$"
marker_a="m9-before-backup-$run"; marker_b="m9-after-backup-$run"
protected="m9-protected-$run"; post_target="m9-after-target-$run"; restore_point="m9_before_delete_${run//[-:]/_}"
write_state MARKER_A "$marker_a"; write_state MARKER_B "$marker_b"; write_state PROTECTED_MARKER "$protected"; write_state POST_TARGET_MARKER "$post_target"; write_state RESTORE_POINT "$restore_point"
leader=$(current_leader); leader_ip=$(name_ip "$leader")
haproxy_sql "CREATE SCHEMA IF NOT EXISTS m9_recovery; CREATE TABLE IF NOT EXISTS m9_recovery.markers(marker text PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT clock_timestamp()); INSERT INTO m9_recovery.markers(marker) VALUES('$marker_a');" >/dev/null
"$PGSENTRY_ROOT/scripts/backup/full.sh" "$profile"
haproxy_sql "INSERT INTO m9_recovery.markers(marker) VALUES('$marker_b');" >/dev/null
wal_after_backup=$(force_archive)
"$PGSENTRY_ROOT/scripts/backup/restore.sh" "$profile" latest
"$PGSENTRY_ROOT/scripts/backup/verify-restore.sh" "$profile" latest
"$PGSENTRY_ROOT/scripts/backup/clean.sh" "$profile" restore
haproxy_sql "INSERT INTO m9_recovery.markers(marker) VALUES('$protected');" >/dev/null
target_row=$(haproxy_sql "SELECT pg_create_restore_point('$restore_point')::text || '|' || clock_timestamp()::text || '|' || pg_current_wal_lsn()::text")
write_state TARGET_SERVER_EVIDENCE "$target_row"
haproxy_sql "INSERT INTO m9_recovery.markers(marker) VALUES('$post_target'); DELETE FROM m9_recovery.markers WHERE marker='$protected';" >/dev/null
for ip in "${PG_IPS[@]}"; do wait_replica_value "$ip" "$protected" 0; done
wal_after_delete=$(force_archive)
"$PGSENTRY_ROOT/scripts/backup/archive-verify.sh" "$profile"
"$PGSENTRY_ROOT/scripts/backup/restore.sh" "$profile" pitr
"$PGSENTRY_ROOT/scripts/backup/verify-restore.sh" "$profile" pitr
jq -n --arg run "$run" --arg a "$marker_a" --arg b "$marker_b" --arg protected "$protected" --arg post "$post_target" --arg target "$restore_point" --arg target_evidence "$target_row" --arg wal_b "$wal_after_backup" --arg wal_delete "$wal_after_delete" --arg leader "$leader" '{run:$run,timeline:[{event:"marker_a",value:$a},{event:"full_backup"},{event:"marker_b",value:$b,archived_wal:$wal_b},{event:"protected_row",value:$protected},{event:"restore_point",name:$target,server_evidence:$target_evidence},{event:"post_target_insert",value:$post},{event:"delete",sql:("DELETE FROM m9_recovery.markers WHERE marker=\u0027"+$protected+"\u0027"),archived_wal:$wal_delete}],live_after_delete:{leader:$leader,primary:"absent",replica_1:"absent",replica_2:"absent"},pitr:{protected_row:"present",post_target_row:"absent"}}' | tee "$BACKUP_RUNTIME/pitr.json"
"$PGSENTRY_ROOT/scripts/etcd/verify.sh" "$profile"
"$PGSENTRY_ROOT/scripts/ha/verify-patroni.sh" "$profile"
"$PGSENTRY_ROOT/scripts/ha/verify-haproxy.sh" "$profile"
"$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" async --quiet
haproxy_sql "INSERT INTO m9_recovery.markers(marker) VALUES('m9-final-health-$run');" >/dev/null
jq -n --arg run "$run" '{run:$run,etcd_healthy:3,patroni_leaders:1,streaming_replicas:2,haproxy_writable_backends:1,routed_write:"passed",durability:"async"}' | tee "$BACKUP_RUNTIME/final-health.json"
"$PGSENTRY_ROOT/scripts/backup/clean.sh" "$profile" restore
trap - EXIT INT TERM
echo "m9_acceptance=passed evidence=$BACKUP_RUNTIME"
