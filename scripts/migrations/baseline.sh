#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../durability/common.sh"; profile=${1:-full}; durability_load "$profile"
"$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" async --quiet
leader=$(leader_name); blocked=$(sql "$(name_ip "$leader")" "select count(*) from pg_stat_activity where application_name like 'pgsafe-m8%' and wait_event_type='Lock'")
[[ $blocked -eq 0 ]]; echo "migration_baseline=healthy leader=$leader blocked_m8_sessions=$blocked"
