#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; profile=$1; action=$2; target=$3; shift 3; chaos_load "$profile"
case "$action" in
  isolate-dcs) for dst in "${ETCD_IPS[@]}"; do ssh_node "$(name_ip "$target")" "sudo iptables -I OUTPUT -p tcp -d '$dst' --dport 2379 -m comment --comment '$CHAOS_TAG' -j REJECT"; done ;;
  restore-dcs) for dst in "${ETCD_IPS[@]}"; do ssh_node "$(name_ip "$target")" "sudo iptables -D OUTPUT -p tcp -d '$dst' --dport 2379 -m comment --comment '$CHAOS_TAG' -j REJECT" || true; done ;;
  isolate-etcd-peer) for peer in "$@"; do ssh_node "$target" "sudo iptables -I OUTPUT -p tcp -d '$peer' --dport 2380 -m comment --comment '$CHAOS_TAG' -j REJECT; sudo iptables -I INPUT -p tcp -s '$peer' --dport 2380 -m comment --comment '$CHAOS_TAG' -j REJECT"; done ;;
  restore-etcd-peer) for peer in "$@"; do ssh_node "$target" "sudo iptables -D OUTPUT -p tcp -d '$peer' --dport 2380 -m comment --comment '$CHAOS_TAG' -j REJECT || true; sudo iptables -D INPUT -p tcp -s '$peer' --dport 2380 -m comment --comment '$CHAOS_TAG' -j REJECT || true"; done ;;
  isolate-replication) for source in "$@"; do ssh_node "$(name_ip "$target")" "sudo iptables -I INPUT -p tcp -s '$source' --dport 5432 -m comment --comment '$CHAOS_TAG' -j REJECT"; done ;;
  restore-replication) for source in "$@"; do ssh_node "$(name_ip "$target")" "sudo iptables -D INPUT -p tcp -s '$source' --dport 5432 -m comment --comment '$CHAOS_TAG' -j REJECT" || true; done ;;
  *) echo "unknown chaos action: $action" >&2; exit 2 ;;
esac
