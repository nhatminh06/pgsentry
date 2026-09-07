#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
profile=${1:-}; scenario=${2:-}; trial=${3:-1}; chaos_load "$profile"
case "$scenario" in primary-dcs-isolation|replica-dcs-isolation|dcs-quorum-loss|etcd-leader-peer-isolation|replication-partition) ;; *) echo 'invalid chaos scenario' >&2; exit 2;; esac
[[ $profile == full ]] || { echo 'canonical M7 scenarios require PROFILE=full' >&2; exit 2; }
"$PGSENTRY_ROOT/scripts/chaos/baseline.sh" "$profile"
run_id="${scenario}-t${trial}-$(date -u +%Y%m%dT%H%M%SZ)"; dir="$CHAOS_RUNTIME/$run_id"; mkdir -p "$dir"; chmod 700 "$dir"
events="$dir/workload.jsonl"; observations="$dir/roles.jsonl"; stop="/tmp/$run_id.stop"; remote="/tmp/$run_id-workload.py"
old=$(leader_name); new=$old; target=; fault=; peers=(); started_at=$(date -u +%FT%TZ)
restore_fault() {
  case "$fault" in
    dcs) "$PGSENTRY_ROOT/scripts/chaos/inject.sh" "$profile" restore-dcs "$target" ;;
    peer) "$PGSENTRY_ROOT/scripts/chaos/inject.sh" "$profile" restore-etcd-peer "$target" "${peers[@]}" ;;
    replication) "$PGSENTRY_ROOT/scripts/chaos/inject.sh" "$profile" restore-replication "$target" "${peers[@]}" ;;
    etcd-services) for ip in "${peers[@]}"; do ssh_node "$ip" 'sudo systemctl start etcd'; done ;;
    '') ;;
  esac
  fault=
}
cleanup() {
  echo "cleanup: restoring M7 fault=${fault:-none}" >&2; set +e; restore_fault
  ssh_node "$CONTROL_IP" "touch '$stop'" 2>/dev/null
  [[ -n ${WORKLOAD_PID:-} ]] && wait "$WORKLOAD_PID" 2>/dev/null
  ssh_node "$CONTROL_IP" "rm -f '$stop' '$remote'" 2>/dev/null; assert_no_chaos_rules
}
trap cleanup EXIT INT TERM
sample_for() { local end=$((SECONDS + $1)); while (( SECONDS < end )); do observe_roles "$observations"; sleep 1; done; }
wait_etcd_at_most() { local count; for _ in $(seq 1 45); do count=$(etcd_healthy_count "$profile" 2>/dev/null || echo 0); (( count <= $1 )) && return; sleep 1; done; return 1; }
wait_etcd_exactly() { local count; for _ in $(seq 1 90); do count=$(etcd_healthy_count "$profile" 2>/dev/null || echo 0); [[ $count -eq $1 ]] && return; sleep 1; done; return 1; }
etcd_status() { source "$PGSENTRY_ROOT/scripts/etcd/common.sh"; load_profile "$profile"; etcdctl_cmd endpoint status --cluster -w json; }
etcd_leader_ip() { jq -r '.[]|select(.Status.header.member_id==.Status.leader)|.Endpoint' | sed -E 's#^https?://([^:]+):.*#\1#' | head -1; }

start_workload "$run_id" "$events" "$stop" "$remote" async; wait_workload_successes "$events" 8; observe_roles "$observations"
initial_etcd_leader=$(etcd_status | etcd_leader_ip); [[ -n $initial_etcd_leader ]]
failure_ns=$(monotonic_ns); failure_at=$(date -u +%FT%TZ)
case "$scenario" in
  primary-dcs-isolation)
    target=$old; fault=dcs; "$PGSENTRY_ROOT/scripts/chaos/inject.sh" "$profile" isolate-dcs "$target"; sample_for 35
    new=$(wait_new_leader "$old"); wait_haproxy_primary "$new"; wait_success_after "$events" "$failure_ns" ;;
  replica-dcs-isolation)
    for candidate in "${PG_NAMES[@]}"; do [[ $candidate == "$old" ]] || { target=$candidate; break; }; done
    fault=dcs; "$PGSENTRY_ROOT/scripts/chaos/inject.sh" "$profile" isolate-dcs "$target"; sample_for 30
    [[ $(leader_name) == "$old" ]]; wait_success_after "$events" "$failure_ns" ;;
  dcs-quorum-loss)
    target="${ETCD_IPS[0]},${ETCD_IPS[1]}"; peers=("${ETCD_IPS[0]}" "${ETCD_IPS[1]}"); fault=etcd-services
    for ip in "${peers[@]}"; do ssh_node "$ip" 'sudo systemctl stop etcd'; done
    wait_etcd_at_most 1; sample_for 40; restore_fault; wait_etcd_exactly 3; wait_cluster
    wait_haproxy_primary "$(leader_name)"; wait_success_after "$events" "$failure_ns"; new=$(leader_name) ;;
  etcd-leader-peer-isolation)
    target=$initial_etcd_leader; fault=peer; for ip in "${ETCD_IPS[@]}"; do [[ $ip == "$target" ]] || peers+=("$ip"); done
    "$PGSENTRY_ROOT/scripts/chaos/inject.sh" "$profile" isolate-etcd-peer "$target" "${peers[@]}"; wait_etcd_exactly 2; sample_for 30
    majority_endpoints="https://${peers[0]}:2379,https://${peers[1]}:2379"
    replacement_etcd_leader=$(PGSENTRY_ETCD_ENDPOINTS="$majority_endpoints" etcd_status 2>/dev/null | etcd_leader_ip || true)
    [[ -n $replacement_etcd_leader && $replacement_etcd_leader != "$initial_etcd_leader" ]]; [[ $(leader_name) == "$old" ]]; wait_success_after "$events" "$failure_ns" ;;
  replication-partition)
    target=$old; fault=replication; for i in 0 1 2; do [[ ${PG_NAMES[$i]} == "$old" ]] || peers+=("${PG_IPS[$i]}"); done
    "$PGSENTRY_ROOT/scripts/chaos/inject.sh" "$profile" isolate-replication "$target" "${peers[@]}"
    connected=9; for _ in $(seq 1 30); do connected=$(sql "$(name_ip "$old")" "select count(*) from pg_stat_replication where state='streaming'" 2>/dev/null || echo 9); [[ $connected -eq 0 ]] && break; observe_roles "$observations"; sleep 1; done
    [[ $connected -eq 0 ]]; sample_for 15; [[ $(leader_name) == "$old" ]]; wait_success_after "$events" "$failure_ns" ;;
esac
restore_fault; wait_etcd_exactly 3; wait_cluster; wait_haproxy_primary "$(leader_name)"; wait_success_after "$events" "$failure_ns"; sample_for 5
sleep 2; stop_workload "$stop" "$remote"; new=$(leader_name)
present=$(sql "$(name_ip "$new")" "select coalesce(string_agg(seq::text,',' order by seq),'') from public.m5_probe where run_id='$run_id'")
metrics=$(python3 "$PGSENTRY_ROOT/scripts/failures/analyze.py" "$events" --failure-ns "$failure_ns" --present "$present"); maximum=$(max_writable "$observations"); [[ $maximum -le 1 ]]
"$PGSENTRY_ROOT/scripts/chaos/baseline.sh" "$profile" >/dev/null; final_state=$(cluster_json)
final_primary=$(jq '[.[]|select(.Role=="Leader")]|length' <<<"$final_state"); final_replicas=$(jq '[.[]|select(.Role|test("Replica"))]|length' <<<"$final_state")
jq -cn --arg scenario "$scenario" --arg run_id "$run_id" --argjson trial "$trial" --arg started "$started_at" --arg failure_at "$failure_at" --arg old "$old" --arg new "$new" --arg target "$target" --arg etcd "$initial_etcd_leader" --argjson failure_ns "$failure_ns" --argjson maximum "$maximum" --argjson metrics "$metrics" --argjson primary "$final_primary" --argjson replicas "$final_replicas" '{scenario:$scenario,run_id:$run_id,trial:$trial,started_at:$started,failure_injected_at:$failure_at,failure_injected_monotonic_ns:$failure_ns,old_primary:$old,new_primary:$new,target:$target,initial_etcd_leader:$etcd,maximum_writable_primaries_observed:$maximum,final_primary_count:$primary,final_replica_count:$replicas,final_etcd_healthy:3,final_haproxy_writable_backends:1,result:"passed"}+$metrics' | tee "$dir/result.json"
trap - EXIT INT TERM
