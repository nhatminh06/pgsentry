#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; backup_load "${1:-}"
leader_pgbackrest check
leader_pgbackrest 'info --output=json' | tee "$BACKUP_RUNTIME/inventory.json"
