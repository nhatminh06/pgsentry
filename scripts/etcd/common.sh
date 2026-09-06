#!/usr/bin/env bash
set -euo pipefail

PGSENTRY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PGSENTRY_RUNTIME="$PGSENTRY_ROOT/.pgsentry"
ETCD_RUNTIME="$PGSENTRY_RUNTIME/etcd"
PGSENTRY_SSH_KEY=${PGSENTRY_SSH_KEY:-$HOME/.ssh/id_ed25519}
PGSENTRY_SSH_USER=${PGSENTRY_SSH_USER:-pgsentry}
ETCD_VERSION=v3.7.1
ETCD_SHA256=e8cd3fa8064c98137c5dbd78b76f969417ace84efb83c481041d7a52ffdd8fb9
ETCD_CLUSTER_TOKEN=pgsentry-m3-etcd

load_profile() {
  mkdir -p "$ETCD_RUNTIME"; chmod 700 "$PGSENTRY_RUNTIME" "$ETCD_RUNTIME"
  case "${1:-}" in
    full) ETCD_NAMES=(etcd-01 etcd-02 etcd-03); ETCD_IPS=(192.168.130.21 192.168.130.22 192.168.130.23); ETCD_SUBNET=192.168.130.0/24 ;;
    colocated) ETCD_NAMES=(node-01 node-02 node-03); ETCD_IPS=(192.168.131.11 192.168.131.12 192.168.131.13); ETCD_SUBNET=192.168.131.0/24 ;;
    *) echo "profile must be 'full' or 'colocated'" >&2; exit 2 ;;
  esac
  ETCD_ENDPOINTS="https://${ETCD_IPS[0]}:2379,https://${ETCD_IPS[1]}:2379,https://${ETCD_IPS[2]}:2379"
}

ssh_node() { ssh -i "$PGSENTRY_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$PGSENTRY_RUNTIME/known_hosts" "$PGSENTRY_SSH_USER@$1" "${@:2}"; }
wait_for_ssh() { for _ in $(seq 1 30); do ssh_node "$1" true 2>/dev/null && return; sleep 5; done; echo "SSH unavailable: $1" >&2; return 1; }
run_remote_script() { local ip=$1 script=$2; shift 2; ssh -i "$PGSENTRY_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$PGSENTRY_RUNTIME/known_hosts" "$PGSENTRY_SSH_USER@$ip" "bash -s -- $*" <"$script"; }
copy_remote() { local ip=$1 src=$2 dest=$3 mode=$4 encoded; encoded=$(base64 -w0 "$src"); ssh_node "$ip" "printf %s '$encoded' | base64 -d | sudo tee '$dest' >/dev/null; sudo chmod '$mode' '$dest'"; }
etcdctl_cmd() { "$ETCD_RUNTIME/etcdctl" --endpoints="${PGSENTRY_ETCD_ENDPOINTS:-$ETCD_ENDPOINTS}" --cacert="$ETCD_RUNTIME/pki/ca.crt" --cert="$ETCD_RUNTIME/pki/admin.crt" --key="$ETCD_RUNTIME/pki/admin.key" --dial-timeout=3s --command-timeout=5s "$@"; }
healthy_count() { etcdctl_cmd endpoint health 2>&1 | grep -c 'is healthy' || true; }
wait_healthy() { local want=$1; for _ in $(seq 1 30); do [[ $(healthy_count) -eq $want ]] && return; sleep 2; done; etcdctl_cmd endpoint health || true; echo "expected $want healthy endpoints" >&2; return 1; }

prepare_pki() {
  local pki="$ETCD_RUNTIME/pki" ext name ip
  [[ -s $pki/ca.crt && -s $pki/admin.crt ]] && return
  umask 077; mkdir -p "$pki"
  openssl genrsa -out "$pki/ca.key" 3072 >/dev/null 2>&1
  openssl req -x509 -new -key "$pki/ca.key" -sha256 -days 3650 -subj '/CN=pgsentry-m3-ca' -out "$pki/ca.crt"
  openssl genrsa -out "$pki/admin.key" 2048 >/dev/null 2>&1
  openssl req -new -key "$pki/admin.key" -subj '/CN=pgsentry-m3-admin' -out "$pki/admin.csr"
  printf 'extendedKeyUsage=clientAuth\n' >"$pki/admin.ext"
  openssl x509 -req -in "$pki/admin.csr" -CA "$pki/ca.crt" -CAkey "$pki/ca.key" -CAcreateserial -days 825 -sha256 -extfile "$pki/admin.ext" -out "$pki/admin.crt" >/dev/null 2>&1
  for i in 0 1 2; do
    name=${ETCD_NAMES[$i]}; ip=${ETCD_IPS[$i]}
    for purpose in server peer; do
      openssl genrsa -out "$pki/$name-$purpose.key" 2048 >/dev/null 2>&1
      openssl req -new -key "$pki/$name-$purpose.key" -subj "/CN=$name-$purpose" -out "$pki/$name-$purpose.csr"
      if [[ $purpose == server ]]; then ext='serverAuth,clientAuth'; else ext='serverAuth,clientAuth'; fi
      printf 'subjectAltName=DNS:%s,IP:%s\nextendedKeyUsage=%s\n' "$name" "$ip" "$ext" >"$pki/$name-$purpose.ext"
      openssl x509 -req -in "$pki/$name-$purpose.csr" -CA "$pki/ca.crt" -CAkey "$pki/ca.key" -CAcreateserial -days 825 -sha256 -extfile "$pki/$name-$purpose.ext" -out "$pki/$name-$purpose.crt" >/dev/null 2>&1
    done
  done
}
