#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; backup_load "${1:-}"
leader=$(current_leader); ip=$(name_ip "$leader"); start=$(date +%s%3N)
leader_pgbackrest 'backup --type=full'
duration=$(( $(date +%s%3N)-start ))
info=$(leader_pgbackrest 'info --output=json')
label=$(jq -r '.[0].backup[-1].label' <<<"$info")
size=$(jq -r '.[0].backup[-1].info.size' <<<"$info")
start_time=$(jq -r '.[0].backup[-1].timestamp.start' <<<"$info")
stop_time=$(jq -r '.[0].backup[-1].timestamp.stop' <<<"$info")
system_id=$(ssh_node "$ip" "sudo -u postgres /usr/lib/postgresql/16/bin/pg_controldata /var/lib/postgresql/16/patroni | awk -F: '/Database system identifier/{gsub(/ /,\"\",\$2);print \$2}'")
write_state BACKUP_LABEL "$label"
jq -n --arg label "$label" --arg leader "$leader" --arg ip "$ip" --arg system_id "$system_id" --arg pg "$(sql "$ip" 'SHOW server_version')" --argjson start "$start_time" --argjson stop "$stop_time" --argjson duration_ms "$duration" --argjson size_bytes "$size" '{stanza:"pgsentry",type:"full",label:$label,source:{member:$leader,address:$ip},timestamp:{start:$start,stop:$stop},duration_ms:$duration_ms,size_bytes:$size_bytes,system_identifier:$system_id,postgresql:$pg}' | tee "$BACKUP_RUNTIME/backup.json"
