#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; profile=${1:-}; mode=${2:-}; backup_load "$profile"
[[ $mode == latest || $mode == pitr ]] || { echo 'mode must be latest or pitr' >&2; exit 2; }
load_state
target=''
[[ $mode == latest ]] || target=${RESTORE_POINT:?PITR restore point missing from state}
start=$(date +%s%3N)
output=$(run_remote_script "$CONTROL_IP" "$PGSENTRY_ROOT/scripts/backup/restore-node.sh" "$mode" "$BACKUP_REPO" "$RESTORE_ROOT" "$RESTORE_PORT" "$BACKUP_STANZA" "$target")
duration=$(( $(date +%s%3N)-start ))
recovery=$(ssh_node "$CONTROL_IP" "sudo -u postgres psql -p $RESTORE_PORT -Atqc 'SELECT pg_is_in_recovery()'")
[[ $recovery == f ]]
system_id=$(ssh_node "$CONTROL_IP" "sudo -u postgres /usr/lib/postgresql/16/bin/pg_controldata '$RESTORE_ROOT/$mode' | awk -F: '/Database system identifier/{gsub(/ /,\"\",\$2);print \$2}'")
jq -n --arg mode "$mode" --arg data "$RESTORE_ROOT/$mode" --arg target "$target" --arg backup "$BACKUP_LABEL" --arg system_id "$system_id" --arg output "$output" --argjson duration_ms "$duration" '{mode:$mode,host:"control-01",address:"127.0.0.1",port:55432,pgdata:$data,source_backup:$backup,target:(if $target=="" then null else $target end),duration_ms:$duration_ms,pg_is_in_recovery:false,system_identifier:$system_id,tool_output:$output}' | tee "$BACKUP_RUNTIME/restore-$mode.json"
