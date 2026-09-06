#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
profile=${1:-}; mode=${2:-}; quiet=${3:-}; validate_mode "$mode"; durability_load "$profile"; "$PGSENTRY_ROOT/scripts/failures/baseline.sh" "$profile" >/dev/null
config=$(dynamic_config); leader=$(leader_name); leader_ip=$(name_ip "$leader"); replication=$(replication_json)
sync_mode=$(jq -r '.synchronous_mode // "off"' <<<"$config"); strict=$(jq -r '.synchronous_mode_strict // false' <<<"$config"); count=$(jq -r '.synchronous_node_count // 1' <<<"$config")
commit=$(sql "$leader_ip" 'show synchronous_commit'); names=$(sql "$leader_ip" 'show synchronous_standby_names'); sync_count=$(jq '[.[]|select(.state=="streaming" and .sync_state=="sync")]|length' <<<"$replication")
[[ $commit == on && $count -eq 1 ]]
case "$mode" in
  async) [[ $sync_mode == off || $sync_mode == false ]]; [[ $strict == false && -z $names && $sync_count -eq 0 ]] ;;
  sync) [[ $sync_mode == on || $sync_mode == true ]]; [[ $strict == false && -n $names && $sync_count -eq 1 ]] ;;
  sync-strict) [[ $sync_mode == on || $sync_mode == true ]]; [[ $strict == true && -n $names && $sync_count -eq 1 ]] ;;
esac
[[ $quiet == --quiet ]] || jq -cn --arg policy "$mode" --arg leader "$leader" --arg names "$names" --arg commit "$commit" --argjson config "$config" --argjson replication "$replication" '{policy:$policy,leader:$leader,synchronous_commit:$commit,synchronous_standby_names:$names,dynamic_configuration:$config,pg_stat_replication:$replication}'
