#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
profile=${1:-}; mode=${2:-}; scenario=${3:-}; trial=${4:-1}; validate_mode "$mode"; durability_load "$profile"
case "$scenario" in primary-vm-loss) [[ $mode == async || $mode == sync ]] ;; synchronous-standby-loss) [[ $mode == sync ]] ;; no-synchronous-standby) [[ $mode == sync-strict ]] ;; *) echo 'invalid durability scenario/policy' >&2; exit 2;; esac
"$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" "$mode" --quiet
run_id="$mode-$scenario-t$trial-$(date -u +%Y%m%dT%H%M%SZ)"; dir="$DURABILITY_RUNTIME/$run_id"; mkdir -p "$dir"; events="$dir/workload.jsonl"; stop="/tmp/$run_id.stop"; remote="/tmp/$run_id-workload.py"
old=$(leader_name); old_ip=$(name_ip "$old"); pre_sync=$(sync_standby); new=$old; replacement_sync=; recovery=not_applicable; removed=(); removed_members=; failure_ns=; failure_epoch=; resumed_ns=null; replacement_ns=null
cleanup() {
  ssh_node "$CONTROL_IP" "touch '$stop'" 2>/dev/null || true
  for node in "${removed[@]}"; do
    if virsh -c qemu:///system domstate "$node" 2>/dev/null | grep -q 'shut off'; then virsh -c qemu:///system start "$node" || true; else ssh_node "$(name_ip "$node")" 'sudo systemctl start patroni' || true; fi
  done
}
trap cleanup EXIT INT TERM
start_workload "$run_id" "$events" "$stop" "$remote" "$mode"; wait_workload_successes "$events" 8
failure_ns=$(monotonic_ns); failure_epoch=$(date +%s)
case "$scenario" in
  primary-vm-loss)
    removed=("$old"); virsh -c qemu:///system destroy "$old"
    new=$(wait_new_leader "$old"); wait_haproxy_primary "$new"; wait_success_after "$events" "$failure_ns"
    virsh -c qemu:///system start "$old"; removed=(); wait_for_ssh "$old_ip"; wait_cluster; recovery=$(classify_rejoin "$old_ip" "$failure_epoch")
    ;;
  synchronous-standby-loss)
    [[ -n $pre_sync ]]; removed=("$pre_sync"); removed_members=$pre_sync; ssh_node "$(name_ip "$pre_sync")" 'sudo systemctl stop patroni'
    for _ in $(seq 1 45); do replacement_sync=$(sync_standby 2>/dev/null || true); [[ -n $replacement_sync && $replacement_sync != "$pre_sync" ]] && break; sleep 1; done
    [[ -n $replacement_sync && $replacement_sync != "$pre_sync" ]]; replacement_ns=$(monotonic_ns); wait_success_after "$events" "$failure_ns"
    ssh_node "$(name_ip "$pre_sync")" 'sudo systemctl start patroni'; removed=(); wait_cluster; wait_policy "$mode"
    ;;
  no-synchronous-standby)
    for node in "${PG_NAMES[@]}"; do [[ $node == "$old" ]] || removed+=("$node"); done
    removed_members=$(IFS=,; echo "${removed[*]}")
    for node in "${removed[@]}"; do ssh_node "$(name_ip "$node")" 'sudo systemctl stop patroni'; done
    for _ in $(seq 1 40); do connected=$(sql "$old_ip" "select count(*) from pg_stat_replication where state='streaming'" 2>/dev/null || echo 9); [[ $connected -eq 0 ]] && break; sleep 1; done
    [[ $connected -eq 0 ]]; no_sync_ns=$(monotonic_ns); names_without_standby=$(sql "$old_ip" 'show synchronous_standby_names'); sleep 12
    successes_without_sync=$(jq -s --argjson t "$no_sync_ns" '[.[]|select(.kind=="write" and .outcome=="confirmed_success" and .attempt_started_ns >= $t)]|length' "$events")
    [[ $successes_without_sync -eq 0 ]]
    first_restore=${removed[0]}; second_restore=${removed[1]}; ssh_node "$(name_ip "$first_restore")" 'sudo systemctl start patroni'; removed=("$second_restore")
    for _ in $(seq 1 60); do replacement_sync=$(sync_standby 2>/dev/null || true); [[ -n $replacement_sync ]] && break; sleep 1; done
    [[ -n $replacement_sync ]]; replacement_ns=$(monotonic_ns); wait_success_after "$events" "$failure_ns"; resumed_ns=$(monotonic_ns)
    ssh_node "$(name_ip "$second_restore")" 'sudo systemctl start patroni'; removed=(); wait_cluster; wait_policy "$mode"
    ;;
esac
sleep 2; stop_workload "$stop" "$remote"
leader=$(leader_name); present=$(sql "$(name_ip "$leader")" "select coalesce(string_agg(seq::text,',' order by seq),'') from public.m5_probe where run_id='$run_id'"); metrics=$(python3 "$PGSENTRY_ROOT/scripts/failures/analyze.py" "$events" --failure-ns "$failure_ns" --present "$present")
"$PGSENTRY_ROOT/scripts/durability/verify.sh" "$profile" "$mode" --quiet
jq -cn --arg policy "$mode" --arg scenario "$scenario" --arg run_id "$run_id" --argjson trial "$trial" --arg old "$old" --arg new "$new" --arg pre_sync "$pre_sync" --arg replacement "$replacement_sync" --arg removed "$removed_members" --arg recovery "$recovery" --arg names_without "${names_without_standby:-}" --argjson failure_ns "$failure_ns" --argjson replacement_ns "$replacement_ns" --argjson resumed_ns "$resumed_ns" --argjson unsafe_successes "${successes_without_sync:-0}" --argjson metrics "$metrics" '{policy:$policy,scenario:$scenario,run_id:$run_id,trial:$trial,old_primary:$old,new_primary:$new,pre_failure_synchronous_standby:$pre_sync,promoted_node_was_synchronous:($pre_sync!="" and $new==$pre_sync),removed_members:($removed|split(",")|map(select(length>0))),replacement_synchronous_standby:$replacement,synchronous_replacement_observed_monotonic_ns:$replacement_ns,synchronous_replacement_ms:(if $replacement_ns==null then null else (($replacement_ns-$failure_ns)/1000000) end),recovery_mechanism:$recovery,failure_injected_monotonic_ns:$failure_ns,first_resumed_observation_ns:$resumed_ns,synchronous_standby_names_without_connected_standby:$names_without,connected_streaming_standbys_without_sync:(if $scenario=="no-synchronous-standby" then 0 else null end),successful_acknowledgements_without_sync:$unsafe_successes,result:"passed"}+$metrics' | tee "$dir/result.json"
trap - EXIT INT TERM
