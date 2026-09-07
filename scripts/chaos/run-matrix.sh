#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd); profile=${1:-full}
for scenario in primary-dcs-isolation replica-dcs-isolation dcs-quorum-loss etcd-leader-peer-isolation replication-partition; do "$root/scripts/chaos/scenario.sh" "$profile" "$scenario" 1; done
python3 "$root/scripts/chaos/report.py" "$root/.pgsentry/results/m7"
