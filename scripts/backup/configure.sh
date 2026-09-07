#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; backup_load "${1:-}"
wait_cluster
run_remote_script "$CONTROL_IP" "$PGSENTRY_ROOT/scripts/backup/configure-control.sh" "$PGBACKREST_VERSION" "$SUBNET" "$BACKUP_REPO" "$RESTORE_ROOT" "$BACKUP_STANZA"
for ip in "${PG_IPS[@]}"; do
  run_remote_script "$ip" "$PGSENTRY_ROOT/scripts/backup/configure-node.sh" "$PGBACKREST_VERSION" "$CONTROL_IP" "$BACKUP_REPO" "$BACKUP_STANZA"
done
config_ip=$(current_leader_ip)
ssh_node "$config_ip" "sudo /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml edit-config --force --set postgresql.parameters.archive_mode=on --set 'postgresql.parameters.archive_command=pgbackrest --stanza=$BACKUP_STANZA archive-push %p' --set postgresql.parameters.archive_timeout=60s $PATRONI_SCOPE" >/dev/null
leader=$(current_leader)
for member in "${PG_NAMES[@]}"; do [[ $member == "$leader" ]] || patronictl restart "$PATRONI_SCOPE" "$member" --force; wait_cluster; done
patronictl restart "$PATRONI_SCOPE" "$leader" --force
wait_cluster
leader_pgbackrest stanza-create
leader_pgbackrest check
"$PGSENTRY_ROOT/scripts/backup/archive-verify.sh" "$1"
echo "backup_configured stanza=$BACKUP_STANZA repository=control-01:$BACKUP_REPO retention_full=2"
