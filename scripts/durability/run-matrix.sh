#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd); profile=${1:-full}
for mode in async sync sync-strict; do "$root/scripts/durability/policy.sh" "$profile" "$mode"; "$root/scripts/durability/policy.sh" "$profile" "$mode"; "$root/scripts/durability/latency.sh" "$profile" "$mode"; done
"$root/scripts/durability/policy.sh" "$profile" async; for trial in 1 2 3; do "$root/scripts/durability/scenario.sh" "$profile" async primary-vm-loss "$trial"; done
"$root/scripts/durability/policy.sh" "$profile" sync; for trial in 1 2 3; do "$root/scripts/durability/scenario.sh" "$profile" sync primary-vm-loss "$trial"; done
"$root/scripts/durability/scenario.sh" "$profile" sync synchronous-standby-loss 1
"$root/scripts/durability/policy.sh" "$profile" sync-strict; "$root/scripts/durability/scenario.sh" "$profile" sync-strict no-synchronous-standby 1
"$root/scripts/durability/policy.sh" "$profile" async
python3 "$root/scripts/durability/report.py" "$root/.pgsentry/results/m6"
