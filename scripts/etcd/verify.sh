#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; load_profile "${1:-}"
members=$(etcdctl_cmd member list -w json)
[[ $(jq '.members | length' <<<"$members") -eq 3 ]]
expected_names=$(printf '%s\n' "${ETCD_NAMES[@]}" | sort | paste -sd,)
[[ $(jq -r '.members[].name' <<<"$members" | sort | paste -sd,) == "$expected_names" ]]
expected_ids=$(jq -r '.members[].ID' <<<"$members" | sort | paste -sd,)
for ip in "${ETCD_IPS[@]}"; do
  endpoint_members=$(PGSENTRY_ETCD_ENDPOINTS="https://$ip:2379" etcdctl_cmd member list -w json)
  [[ $(jq -r '.members[].ID' <<<"$endpoint_members" | sort | paste -sd,) == "$expected_ids" ]]
done
wait_healthy 3
status=$(etcdctl_cmd endpoint status --cluster -w json)
[[ $(jq '[.[].Status.leader] | unique | length' <<<"$status") -eq 1 ]]
[[ $(jq '[.[] | select(.Status.header.member_id == .Status.leader)] | length' <<<"$status") -eq 1 ]]
key="/pgsentry/m3/probe/$(date -u +%Y%m%dT%H%M%SZ)"; value="m3-replicated-${key##*/}"
PGSENTRY_ETCD_ENDPOINTS="https://${ETCD_IPS[0]}:2379" etcdctl_cmd put "$key" "$value" >/dev/null
for ip in "${ETCD_IPS[@]}"; do [[ $(PGSENTRY_ETCD_ENDPOINTS="https://$ip:2379" etcdctl_cmd get "$key" --print-value-only) == "$value" ]]; done
if "$ETCD_RUNTIME/etcdctl" --endpoints="https://${ETCD_IPS[0]}:2379" --cacert="$ETCD_RUNTIME/pki/ca.crt" --dial-timeout=3s --command-timeout=5s endpoint health >/dev/null 2>&1; then
  echo 'client endpoint unexpectedly accepted an unauthenticated TLS client' >&2; exit 1
fi
etcdctl_cmd member list -w table
etcdctl_cmd endpoint status --cluster -w table
echo "replicated_key=$key value=$value observed=3/3"
