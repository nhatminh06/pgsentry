#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; profile=${1:-}; chaos_load "$profile"
run_bounded durability-policy 120 "$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" async --quiet
run_bounded stale-firewall-rules 60 assert_no_chaos_rules
leader=$(run_bounded patroni-leader 30 leader_name)
backend=$(run_bounded haproxy-backend 30 backend_name)
etcd=$(run_bounded etcd-health 45 etcd_healthy_count "$profile")
[[ -n $leader && $backend == "$leader" && $etcd -eq 3 ]]
echo "chaos_baseline=healthy policy=async leader=$leader backend=$backend etcd=$etcd/3"
