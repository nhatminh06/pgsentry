#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; profile=${1:-}; mode=${2:-latest}; backup_load "$profile"; load_state
query() { local encoded; encoded=$(printf %s "$1" | base64 -w0); ssh_node "$CONTROL_IP" "printf %s '$encoded' | base64 -d | sudo -u postgres psql -p $RESTORE_PORT -Atq"; }
ssh_node "$CONTROL_IP" "ss -lnt | grep -q '127.0.0.1:$RESTORE_PORT'"
[[ $(query 'SELECT pg_is_in_recovery()') == f ]]
[[ $(query 'SHOW server_version_num') -ge 160000 ]]
[[ $(query "SELECT count(*) FROM m9_recovery.markers WHERE marker='$MARKER_A'") == 1 ]]
if [[ $mode == latest ]]; then
  [[ $(query "SELECT count(*) FROM m9_recovery.markers WHERE marker='$MARKER_B'") == 1 ]]
else
  [[ $(query "SELECT count(*) FROM m9_recovery.markers WHERE marker='$PROTECTED_MARKER'") == 1 ]]
  [[ $(query "SELECT count(*) FROM m9_recovery.markers WHERE marker='$POST_TARGET_MARKER'") == 0 ]]
fi
members=$(cluster_json | jq 'length'); [[ $members -eq 3 ]]
! cluster_json | jq -e '.[]|select(.Host=="127.0.0.1" or .Port==55432)' >/dev/null
! ssh_node "$CONTROL_IP" "grep -Rqs '55432' /etc/haproxy"
receivers=$(query 'SELECT count(*) FROM pg_stat_wal_receiver'); [[ $receivers -eq 0 ]]
archive_mode=$(query 'SHOW archive_mode'); [[ $archive_mode == off ]]
timeline=$(query 'SELECT timeline_id FROM pg_control_checkpoint()')
jq -n --arg mode "$mode" --arg marker_a "$MARKER_A" --arg marker_b "$MARKER_B" --arg protected "$PROTECTED_MARKER" --arg post_target "$POST_TARGET_MARKER" --arg timeline "$timeline" '{mode:$mode,process_running:true,address:"127.0.0.1",port:55432,recovery_complete:true,marker_a:true,marker_b:(if $mode=="latest" then true else null end),protected_row:(if $mode=="pitr" then "present" else null end),post_target:(if $mode=="pitr" then "absent" else null end),patroni_member:false,haproxy_backend:false,wal_receiver_count:0,archive_mode:"off",timeline:($timeline|tonumber)}' | tee "$BACKUP_RUNTIME/verify-$mode.json"
