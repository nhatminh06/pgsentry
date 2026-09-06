#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
profile=${1:-}; scenario=${2:-}; trial=${3:-1}; failure_load "$profile"
case "$scenario" in primary-service-loss|primary-vm-loss|replica-loss|etcd-member-loss|primary-dcs-isolation|haproxy-loss) ;; *) echo 'invalid scenario' >&2; exit 2;; esac
"$PGSENTRY_ROOT/scripts/failures/baseline.sh" "$profile"
run_id="${scenario}-t${trial}-$(date -u +%Y%m%dT%H%M%SZ)"; dir="$FAILURE_RUNTIME/$run_id"; mkdir -p "$dir"; chmod 700 "$dir"; started_at=$(date -u +%FT%TZ)
events="$dir/workload.jsonl"; remote_stop="/tmp/$run_id.stop"; remote_workload="/tmp/$run_id-workload.py"; observations="$dir/roles.jsonl"; password=$(runtime_secret superuser-password)
old=$(leader_name); old_ip=$(name_ip "$old"); new=$old; recovery=not_applicable; target=; cleanup_action=; leader_observed_ns=null; haproxy_observed_ns=null
cleanup() {
  echo "cleanup: stopping workload and restoring action=${cleanup_action:-none}" >&2
  ssh_node "$CONTROL_IP" "touch '$remote_stop'" 2>/dev/null || echo 'cleanup workload stop failed' >&2
  case "$cleanup_action" in
    patroni) "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-patroni "$target" || echo 'cleanup patroni restart failed' >&2 ;;
    vm) "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-vm "$target" || echo 'cleanup VM start failed' >&2 ;;
    etcd) "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-etcd "$target" || echo 'cleanup etcd restart failed' >&2 ;;
    dcs) "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" restore-dcs "$target" || echo 'cleanup DCS restoration failed' >&2 ;;
    haproxy) "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-haproxy "$target" || echo 'cleanup HAProxy restart failed' >&2 ;;
  esac
}
trap cleanup EXIT INT TERM
encoded_workload=$(base64 -w0 "$PGSENTRY_ROOT/scripts/failures/workload.py")
ssh_node "$CONTROL_IP" "printf %s '$encoded_workload' | base64 -d >'$remote_workload'; rm -f '$remote_stop'"
printf '%s\n' "$password" | ssh_node "$CONTROL_IP" "IFS= read -r PGPASSWORD; export PGPASSWORD; python3 '$remote_workload' --host 127.0.0.1 --port '$HAPROXY_WRITE_PORT' --run-id '$run_id' --events /dev/stdout --stop-file '$remote_stop'" >"$events" & workload_pid=$!
wait_workload_successes "$events" 5
mark_failure() { failure_ns=$(monotonic_ns); failure_epoch=$(date +%s); failure_injected_at=$(date -u +%FT%TZ); }
case "$scenario" in
  primary-service-loss)
    target=$old; cleanup_action=patroni; "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" stop-patroni "$target"; mark_failure
    new=$(wait_new_leader "$old"); leader_observed_ns=$(monotonic_ns); wait_haproxy_primary "$new"; haproxy_observed_ns=$(monotonic_ns); wait_success_after "$events" "$failure_ns"
    "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-patroni "$target"; cleanup_action=; wait_cluster; recovery=$(classify_rejoin "$old_ip" "$failure_epoch") ;;
  primary-vm-loss)
    [[ $profile == full ]]; target=$old; cleanup_action=vm; "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" destroy-vm "$target"; mark_failure
    new=$(wait_new_leader "$old"); leader_observed_ns=$(monotonic_ns); wait_haproxy_primary "$new"; haproxy_observed_ns=$(monotonic_ns); wait_success_after "$events" "$failure_ns"
    "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-vm "$target"; cleanup_action=; wait_for_ssh "$old_ip"; wait_cluster; recovery=$(classify_rejoin "$old_ip" "$failure_epoch") ;;
  replica-loss)
    for candidate in "${PG_NAMES[@]}"; do [[ $candidate == "$old" ]] || { target=$candidate; break; }; done
    cleanup_action=patroni; "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" stop-patroni "$target"; mark_failure; sleep 6
    [[ $(leader_name) == "$old" ]]; wait_success_after "$events" "$failure_ns"
    "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-patroni "$target"; cleanup_action=; wait_cluster; new=$(leader_name); recovery=$(classify_rejoin "$(name_ip "$target")" "$failure_epoch") ;;
  etcd-member-loss)
    target=${ETCD_IPS[0]}; source "$PGSENTRY_ROOT/scripts/etcd/common.sh"; load_profile "$profile"
    status=$(etcdctl_cmd endpoint status --cluster -w json); member_role=$(jq -r --arg endpoint "https://$target:2379" '.[]|select(.Endpoint==$endpoint)|if .Status.header.member_id==.Status.leader then "leader" else "follower" end' <<<"$status")
    cleanup_action=etcd; "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" stop-etcd "$target"; mark_failure; wait_healthy 2; sleep 6
    [[ $(leader_name) == "$old" ]]; wait_success_after "$events" "$failure_ns"
    "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-etcd "$target"; cleanup_action=; wait_healthy 3; wait_cluster; new=$(leader_name); recovery="$member_role" ;;
  primary-dcs-isolation)
    target=$old; cleanup_action=dcs; "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" isolate-dcs "$target"; mark_failure
    max_writable=0
    for _ in $(seq 1 50); do
      count=0; roles='{}'
      for i in 0 1 2; do role=$(sql "${PG_IPS[$i]}" 'select pg_is_in_recovery()' 2>/dev/null || echo unavailable); [[ $role == f ]] && count=$((count+1)); roles=$(jq -c --arg n "${PG_NAMES[$i]}" --arg r "$role" '.+{($n):$r}' <<<"$roles"); done
      (( count > max_writable )) && max_writable=$count
      jq -cn --argjson timestamp_ns "$(monotonic_ns)" --argjson writable "$count" --argjson roles "$roles" '{timestamp_ns:$timestamp_ns,writable_primary_count:$writable,roles:$roles}' >>"$observations"
      (( count > 1 )) && { echo 'split-brain observation: more than one writable primary' >&2; exit 1; }
      candidate=$(leader_name 2>/dev/null || true); [[ -n $candidate && $candidate != "$old" ]] && new=$candidate
      [[ $new != "$old" ]] && wait_haproxy_primary "$new" 2>/dev/null && { leader_observed_ns=$(monotonic_ns); haproxy_observed_ns=$leader_observed_ns; break; }
      sleep 1
    done
    [[ $(etcd_healthy_count "$profile") -eq 3 ]]; [[ $max_writable -le 1 ]]
    "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" restore-dcs "$target"; cleanup_action=; wait_cluster; wait_haproxy_primary "$(leader_name)"; wait_success_after "$events" "$failure_ns"; recovery=$(classify_rejoin "$old_ip" "$failure_epoch") ;;
  haproxy-loss)
    target=$CONTROL_IP; cleanup_action=haproxy; "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" stop-haproxy "$target"; mark_failure; sleep 6
    [[ $(leader_name) == "$old" ]]; [[ $(sql "$old_ip" "select count(*) from pg_stat_replication where state='streaming'") -eq 2 ]]; [[ $(etcd_healthy_count "$profile") -eq 3 ]]
    "$PGSENTRY_ROOT/scripts/failures/inject.sh" "$profile" start-haproxy "$target"; cleanup_action=; wait_haproxy_primary "$old"; wait_success_after "$events" "$failure_ns"; new=$(leader_name) ;;
esac
sleep 2; ssh_node "$CONTROL_IP" "touch '$remote_stop'"; wait "$workload_pid"; ssh_node "$CONTROL_IP" "rm -f '$remote_stop' '$remote_workload'"
leader=$(leader_name); present=$(sql "$(name_ip "$leader")" "select coalesce(string_agg(seq::text,',' order by seq),'') from public.m5_probe where run_id='$run_id'")
metrics=$(python3 "$PGSENTRY_ROOT/scripts/failures/analyze.py" "$events" --failure-ns "$failure_ns" --present "$present")
"$PGSENTRY_ROOT/scripts/failures/baseline.sh" "$profile" >/dev/null
final_state=$(cluster_json); final_primary=$(jq '[.[]|select(.Role=="Leader")]|length' <<<"$final_state"); final_replicas=$(jq '[.[]|select(.Role|test("Replica"))]|length' <<<"$final_state")
jq -cn --arg scenario "$scenario" --arg run_id "$run_id" --argjson trial "$trial" --arg started_at "$started_at" --arg failure_at "$failure_injected_at" --arg old "$old" --arg new "$new" --arg target "$target" --arg recovery "$recovery" --argjson failure_ns "$failure_ns" --argjson leader_ns "$leader_observed_ns" --argjson haproxy_ns "$haproxy_observed_ns" --argjson metrics "$metrics" --argjson primary "$final_primary" --argjson replicas "$final_replicas" '{scenario:$scenario,run_id:$run_id,trial:$trial,started_at:$started_at,failure_injected_at:$failure_at,failure_injected_monotonic_ns:$failure_ns,leader_observed_monotonic_ns:$leader_ns,haproxy_observed_monotonic_ns:$haproxy_ns,old_primary:$old,new_primary:$new,target:$target,recovery_mechanism:$recovery,final_primary_count:$primary,final_replica_count:$replicas,final_etcd_healthy:3,final_haproxy_writable_backends:1,result:"passed"}+$metrics' | tee "$dir/result.json"
trap - EXIT INT TERM
