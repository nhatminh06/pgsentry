#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; profile=$1 action=$2 target=$3; failure_load "$profile"
case "$action" in
  stop-patroni) ssh_node "$(name_ip "$target")" 'sudo systemctl stop patroni' ;;
  start-patroni) ssh_node "$(name_ip "$target")" 'sudo systemctl start patroni' ;;
  destroy-vm) virsh -c qemu:///system destroy "$target" ;;
  start-vm) virsh -c qemu:///system start "$target" ;;
  stop-etcd) ssh_node "$target" 'sudo systemctl stop etcd' ;;
  start-etcd) ssh_node "$target" 'sudo systemctl start etcd' ;;
  stop-haproxy) ssh_node "$CONTROL_IP" 'sudo systemctl stop haproxy' ;;
  start-haproxy) ssh_node "$CONTROL_IP" 'sudo systemctl start haproxy' ;;
  isolate-dcs) for destination in "${ETCD_IPS[@]}"; do ssh_node "$(name_ip "$target")" "sudo iptables -I OUTPUT -p tcp -d '$destination' --dport 2379 -m comment --comment pgsentry-m5-dcs-isolation -j REJECT"; done ;;
  restore-dcs) for destination in "${ETCD_IPS[@]}"; do ssh_node "$(name_ip "$target")" "sudo iptables -D OUTPUT -p tcp -d '$destination' --dport 2379 -m comment --comment pgsentry-m5-dcs-isolation -j REJECT" || true; done ;;
  *) echo "unknown injection action: $action" >&2; exit 2 ;;
esac
