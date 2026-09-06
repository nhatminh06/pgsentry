#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"; load_profile "${1:-}"; prepare_pki
cluster="${ETCD_NAMES[0]}=https://${ETCD_IPS[0]}:2380,${ETCD_NAMES[1]}=https://${ETCD_IPS[1]}:2380,${ETCD_NAMES[2]}=https://${ETCD_IPS[2]}:2380"
for i in 0 1 2; do
  ip=${ETCD_IPS[$i]}; name=${ETCD_NAMES[$i]}; wait_for_ssh "$ip"
  run_remote_script "$ip" "$PGSENTRY_ROOT/scripts/etcd/install-node.sh" "$ETCD_VERSION" "$ETCD_SHA256"
  copy_remote "$ip" "$ETCD_RUNTIME/pki/ca.crt" /etc/etcd/pki/ca.crt 0644
  copy_remote "$ip" "$ETCD_RUNTIME/pki/$name-server.crt" /etc/etcd/pki/server.crt 0644
  copy_remote "$ip" "$ETCD_RUNTIME/pki/$name-server.key" /etc/etcd/pki/server.key 0640
  copy_remote "$ip" "$ETCD_RUNTIME/pki/$name-peer.crt" /etc/etcd/pki/peer.crt 0644
  copy_remote "$ip" "$ETCD_RUNTIME/pki/$name-peer.key" /etc/etcd/pki/peer.key 0640
  ssh_node "$ip" 'sudo chown -R root:etcd /etc/etcd/pki'
  run_remote_script "$ip" "$PGSENTRY_ROOT/scripts/etcd/configure-node.sh" "$name" "$ip" "$cluster" "$ETCD_CLUSTER_TOKEN" "$ETCD_SUBNET"
done
curl -fsSL --retry 3 "https://github.com/etcd-io/etcd/releases/download/$ETCD_VERSION/etcd-$ETCD_VERSION-linux-amd64.tar.gz" -o "$ETCD_RUNTIME/etcd.tar.gz"
echo "$ETCD_SHA256  $ETCD_RUNTIME/etcd.tar.gz" | sha256sum -c -
tar -xzf "$ETCD_RUNTIME/etcd.tar.gz" -C "$ETCD_RUNTIME" --strip-components=1 "etcd-$ETCD_VERSION-linux-amd64/etcdctl"
chmod 700 "$ETCD_RUNTIME/etcdctl"; rm -f "$ETCD_RUNTIME/etcd.tar.gz"
wait_healthy 3
for i in 0 1 2; do ssh_node "${ETCD_IPS[$i]}" 'systemctl is-enabled etcd; systemctl is-active etcd'; done
echo "etcd $ETCD_VERSION configured with three TLS-authenticated members"
