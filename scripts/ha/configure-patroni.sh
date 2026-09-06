#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; load_profile "${1:-}"; prepare_patroni_cert
superpass=$(runtime_secret superuser-password); replpass=$(runtime_secret replication-password)
etcd_hosts=$(IFS=,; echo "${ETCD_IPS[*]}")
for i in 0 1 2; do
  ip=${PG_IPS[$i]}; name=${PG_NAMES[$i]}; wait_for_ssh "$ip"
  run_remote_script "$ip" "$PGSENTRY_ROOT/scripts/ha/install-patroni-node.sh" "$PATRONI_VERSION"
  copy_remote "$ip" "$ETCD_RUNTIME/pki/ca.crt" /etc/patroni/pki/ca.crt 0644
  copy_remote "$ip" "$HA_RUNTIME/patroni-etcd.crt" /etc/patroni/pki/client.crt 0644
  copy_remote "$ip" "$HA_RUNTIME/patroni-etcd.key" /etc/patroni/pki/client.key 0640
  ssh_node "$ip" 'sudo chown -R root:postgres /etc/patroni/pki'
  printf '%s\n%s\n' "$superpass" "$replpass" | run_remote_script_with_input "$ip" "$PGSENTRY_ROOT/scripts/ha/configure-patroni-node.sh" "$name" "$ip" "$SUBNET" "$PATRONI_SCOPE" "$PATRONI_NAMESPACE" "$etcd_hosts"
  [[ $i -eq 0 ]] && sleep 5
done
wait_cluster
echo "Patroni $PATRONI_VERSION owns PostgreSQL on ${PG_NAMES[*]}"
