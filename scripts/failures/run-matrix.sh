#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd); profile=${1:-full}
for trial in 1 2 3; do "$root/scripts/failures/scenario.sh" "$profile" primary-service-loss "$trial"; done
for trial in 1 2 3; do "$root/scripts/failures/scenario.sh" "$profile" primary-vm-loss "$trial"; done
for scenario in replica-loss etcd-member-loss primary-dcs-isolation haproxy-loss; do "$root/scripts/failures/scenario.sh" "$profile" "$scenario" 1; done
python3 "$root/scripts/failures/report.py" "$root/.pgsentry/results/m5"
