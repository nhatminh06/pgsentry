#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
profile=${1:-}; mode=${2:-}; validate_mode "$mode"; durability_load "$profile"; wait_cluster
case "$mode" in
  async) sync=off; strict=false ;;
  sync) sync=on; strict=false ;;
  sync-strict) sync=on; strict=true ;;
esac
patronictl edit-config --force --set "synchronous_mode=$sync" --set "synchronous_mode_strict=$strict" --set synchronous_node_count=1 --set postgresql.parameters.synchronous_commit=on >/dev/null
wait_policy "$mode"
echo "durability_policy=$mode synchronous_mode=$sync synchronous_mode_strict=$strict synchronous_node_count=1 synchronous_commit=on"
