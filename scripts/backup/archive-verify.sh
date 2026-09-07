#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; backup_load "${1:-}"
ip=$(current_leader_ip)
[[ $(sql "$ip" 'SHOW archive_mode') == on ]]
command=$(sql "$ip" 'SHOW archive_command'); [[ $command == *'pgbackrest'*archive-push* ]]
wal=$(force_archive)
leader_pgbackrest check
archiver=$(sql "$ip" "SELECT row_to_json(s) FROM (SELECT archived_count,last_archived_wal,last_archived_time,failed_count,last_failed_wal,last_failed_time FROM pg_stat_archiver) s")
jq -n --arg wal "$wal" --arg command "$command" --argjson archiver "$archiver" '{archive_mode:"on",archive_command:$command,forced_wal:$wal,pg_stat_archiver:$archiver,pgbackrest_check:"passed"}' | tee "$BACKUP_RUNTIME/archive.json"
