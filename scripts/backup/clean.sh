#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; profile=${1:-}; mode=${2:-restore}; backup_load "$profile"
run_remote_script "$CONTROL_IP" "$PGSENTRY_ROOT/scripts/backup/clean-node.sh" "$RESTORE_ROOT" "$mode" "$BACKUP_REPO"
if [[ $mode == all ]]; then
  for ip in "${PG_IPS[@]}"; do ssh_node "$ip" "sudo umount '$BACKUP_REPO' 2>/dev/null || true; sudo sed -i '\|$CONTROL_IP:$BACKUP_REPO $BACKUP_REPO nfs4|d' /etc/fstab"; done
fi
echo "backup_cleanup=$mode complete"
