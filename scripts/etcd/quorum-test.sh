#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; load_profile "${1:-}"
stopped=()
cleanup() { for ip in "${stopped[@]:-}"; do ssh_node "$ip" 'sudo systemctl start etcd' >/dev/null 2>&1 || true; done; }
trap cleanup EXIT INT TERM
wait_healthy 3
before=$(etcdctl_cmd endpoint status --cluster -w json)
leader_id=$(jq -r '.[0].Status.leader' <<<"$before")
leader_ip=$(jq -r --argjson id "$leader_id" '.[] | select(.Status.header.member_id == $id) | .Endpoint | capture("https://(?<ip>[^:]+)").ip' <<<"$before")
leader_name=$(etcdctl_cmd member list -w json | jq -r --argjson id "$leader_id" '.members[] | select(.ID == $id) | .name')
echo "old_leader=$leader_name id=$leader_id endpoint=$leader_ip"
ssh_node "$leader_ip" 'sudo systemctl stop etcd'; stopped+=("$leader_ip"); wait_healthy 2
live_endpoints=()
for ip in "${ETCD_IPS[@]}"; do [[ $ip != "$leader_ip" ]] && live_endpoints+=("https://$ip:2379"); done
live_csv=$(IFS=,; echo "${live_endpoints[*]}")
after=$(PGSENTRY_ETCD_ENDPOINTS="$live_csv" etcdctl_cmd endpoint status -w json); new_id=$(jq -r '.[0].Status.leader' <<<"$after")
[[ $new_id != "$leader_id" && $new_id != 0 ]]
new_name=$(etcdctl_cmd member list -w json | jq -r --argjson id "$new_id" '.members[] | select(.ID == $id) | .name')
one_key="/pgsentry/m3/one-down/$(date -u +%Y%m%dT%H%M%SZ)"; one_value="m3-one-member-down-${one_key##*/}"; etcdctl_cmd put "$one_key" "$one_value" >/dev/null
echo "new_leader=$new_name id=$new_id committed=$one_value"
ssh_node "$leader_ip" 'sudo systemctl start etcd'; stopped=(); wait_healthy 3
[[ $(PGSENTRY_ETCD_ENDPOINTS="https://$leader_ip:2379" etcdctl_cmd get "$one_key" --print-value-only) == "$one_value" ]]
survivor=${ETCD_IPS[0]}; [[ $survivor == "$leader_ip" ]] && survivor=${ETCD_IPS[1]}
down=(); for ip in "${ETCD_IPS[@]}"; do [[ $ip != "$survivor" ]] && down+=("$ip"); done
for ip in "${down[@]}"; do ssh_node "$ip" 'sudo systemctl stop etcd'; stopped+=("$ip"); done
loss_key="/pgsentry/m3/quorum-loss/$(date -u +%Y%m%dT%H%M%SZ)"
if PGSENTRY_ETCD_ENDPOINTS="https://$survivor:2379" etcdctl_cmd put "$loss_key" must-not-commit >"$ETCD_RUNTIME/quorum-write.out" 2>&1; then echo 'write unexpectedly succeeded without quorum' >&2; exit 1; fi
if PGSENTRY_ETCD_ENDPOINTS="https://$survivor:2379" etcdctl_cmd get "$one_key" >"$ETCD_RUNTIME/linearizable-read.out" 2>&1; then echo 'linearizable read unexpectedly succeeded without quorum' >&2; exit 1; fi
serial=$(PGSENTRY_ETCD_ENDPOINTS="https://$survivor:2379" etcdctl_cmd get "$one_key" --consistency=s --print-value-only)
[[ $serial == "$one_value" ]]
echo "quorum_loss_write=$(tail -1 "$ETCD_RUNTIME/quorum-write.out")"
echo "linearizable_read=$(tail -1 "$ETCD_RUNTIME/linearizable-read.out")"
echo "serializable_read=$serial"
ssh_node "${down[0]}" 'sudo systemctl start etcd'; stopped=("${down[1]}"); wait_healthy 2
restore_key="/pgsentry/m3/restored/$(date -u +%Y%m%dT%H%M%SZ)"; restore_value="m3-quorum-restored-${restore_key##*/}"; etcdctl_cmd put "$restore_key" "$restore_value" >/dev/null
ssh_node "${down[1]}" 'sudo systemctl start etcd'; stopped=(); wait_healthy 3
pkey="/pgsentry/m3/persistent/$(date -u +%Y%m%dT%H%M%SZ)"; pvalue="m3-persistent-${pkey##*/}"; etcdctl_cmd put "$pkey" "$pvalue" >/dev/null
for ip in "${ETCD_IPS[@]}"; do ssh_node "$ip" 'sudo systemctl restart etcd'; done
wait_healthy 3; [[ $(etcdctl_cmd get "$pkey" --print-value-only) == "$pvalue" ]]
post_key="/pgsentry/m3/post-restart/$(date -u +%Y%m%dT%H%M%SZ)"; etcdctl_cmd put "$post_key" ok >/dev/null
etcdctl_cmd endpoint status --cluster -w table
echo "quorum_restored=$restore_value persistence=$pvalue final_health=3/3"
