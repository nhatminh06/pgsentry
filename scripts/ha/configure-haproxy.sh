#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; load_profile "${1:-}"; wait_for_ssh "$CONTROL_IP"
run_remote_script "$CONTROL_IP" "$PGSENTRY_ROOT/scripts/ha/configure-haproxy-node.sh" "$SUBNET" "${PG_NAMES[0]}" "${PG_IPS[0]}" "${PG_NAMES[1]}" "${PG_IPS[1]}" "${PG_NAMES[2]}" "${PG_IPS[2]}"
echo "HAProxy write endpoint=$CONTROL_IP:$HAPROXY_WRITE_PORT"
