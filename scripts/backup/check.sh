#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; backup_load "${1:-}"
wait_cluster
leader_pgbackrest check
"$PGSENTRY_ROOT/scripts/backup/archive-verify.sh" "$1"
echo 'backup_health=passed'
