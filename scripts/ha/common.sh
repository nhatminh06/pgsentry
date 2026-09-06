#!/usr/bin/env bash
set -euo pipefail
PGSENTRY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PGSENTRY_RUNTIME="$PGSENTRY_ROOT/.pgsentry"
HA_RUNTIME="$PGSENTRY_RUNTIME/ha"
ETCD_RUNTIME="$PGSENTRY_RUNTIME/etcd"
PGSENTRY_SSH_KEY=${PGSENTRY_SSH_KEY:-$HOME/.ssh/id_ed25519}
PGSENTRY_SSH_USER=${PGSENTRY_SSH_USER:-pgsentry}
PATRONI_VERSION=4.1.5
PATRONI_SCOPE=pgsentry
PATRONI_NAMESPACE=/pgsentry/m4/
HAPROXY_WRITE_PORT=5000

load_profile() {
  mkdir -p "$HA_RUNTIME"; chmod 700 "$PGSENTRY_RUNTIME" "$HA_RUNTIME"
  case "${1:-}" in
    full) PG_NAMES=(pg-01 pg-02 pg-03); PG_IPS=(192.168.130.11 192.168.130.12 192.168.130.13); ETCD_IPS=(192.168.130.21 192.168.130.22 192.168.130.23); CONTROL_IP=192.168.130.31; SUBNET=192.168.130.0/24 ;;
    colocated) PG_NAMES=(node-01 node-02 node-03); PG_IPS=(192.168.131.11 192.168.131.12 192.168.131.13); ETCD_IPS=(192.168.131.11 192.168.131.12 192.168.131.13); CONTROL_IP=192.168.131.11; SUBNET=192.168.131.0/24 ;;
    *) echo "profile must be 'full' or 'colocated'" >&2; exit 2 ;;
  esac
}
ssh_node() { ssh -F /dev/null -i "$PGSENTRY_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$PGSENTRY_RUNTIME/known_hosts" "$PGSENTRY_SSH_USER@$1" "${@:2}"; }
wait_for_ssh() { for _ in $(seq 1 30); do ssh_node "$1" true 2>/dev/null && return; sleep 5; done; echo "SSH unavailable: $1" >&2; return 1; }
run_remote_script() { local ip=$1 script=$2; shift 2; ssh -F /dev/null -i "$PGSENTRY_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$PGSENTRY_RUNTIME/known_hosts" "$PGSENTRY_SSH_USER@$ip" "bash -s -- $*" <"$script"; }
run_remote_script_with_input() { local ip=$1 script=$2 remote=/tmp/pgsentry-ha-script encoded; shift 2; encoded=$(base64 -w0 "$script"); ssh_node "$ip" "printf %s '$encoded' | base64 -d >'$remote'; bash '$remote' $*; status=\$?; rm -f '$remote'; exit \$status"; }
copy_remote() { local ip=$1 src=$2 dest=$3 mode=$4 encoded; encoded=$(base64 -w0 "$src"); ssh_node "$ip" "tmp=\$(mktemp); printf %s '$encoded' | base64 -d >\$tmp; sudo cmp -s \$tmp '$dest' || sudo install -m '$mode' \$tmp '$dest'; rm -f \$tmp"; }
runtime_secret() { local file="$HA_RUNTIME/$1"; if [[ ! -s $file ]]; then umask 077; openssl rand -hex 24 >"$file"; fi; cat "$file"; }
patronictl() {
  local ip
  for ip in "${PG_IPS[@]}"; do
    ssh_node "$ip" 'timeout 8 sudo /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml' "$@" && return
  done
  return 1
}
cluster_json() {
  local ip output
  for ip in "${PG_IPS[@]}"; do
    if output=$(ssh_node "$ip" 'timeout 8 sudo /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list -f json' 2>/dev/null); then
      printf '%s\n' "$output"
      return
    fi
  done
  return 1
}
leader_name() { cluster_json | jq -r '.[] | select(.Role == "Leader") | .Member'; }
name_ip() { for i in 0 1 2; do [[ ${PG_NAMES[$i]} == "$1" ]] && { echo "${PG_IPS[$i]}"; return; }; done; return 1; }
sql() { local ip=$1 query=$2 password encoded; password=$(runtime_secret superuser-password); encoded=$(printf %s "$query" | base64 -w0); ssh_node "$ip" "printf %s '$encoded' | base64 -d | PGPASSWORD='$password' psql -h '$ip' -U postgres -d postgres -Atq"; }
wait_cluster() { local state leaders replicas; for _ in $(seq 1 60); do state=$(cluster_json 2>/dev/null || true); leaders=$(jq '[.[]|select(.Role=="Leader" and .State=="running")]|length' <<<"${state:-[]}" 2>/dev/null || echo 0); replicas=$(jq '[.[]|select(.Role!="Leader" and .State=="streaming")]|length' <<<"${state:-[]}" 2>/dev/null || echo 0); [[ $leaders -eq 1 && $replicas -eq 2 ]] && return; sleep 3; done; patronictl list || true; echo 'Patroni cluster did not reach 1 leader + 2 streaming standbys' >&2; return 1; }
wait_value() { local ip=$1 value=$2; for _ in $(seq 1 40); do [[ $(sql "$ip" "SELECT value FROM public.m4_evidence WHERE value='$value'" 2>/dev/null || true) == "$value" ]] && return; sleep 2; done; echo "value did not reach $ip: $value" >&2; return 1; }
haproxy_sql() { local query=$1 password encoded; password=$(runtime_secret superuser-password); encoded=$(printf %s "$query" | base64 -w0); ssh_node "$CONTROL_IP" "printf %s '$encoded' | base64 -d | PGPASSWORD='$password' psql -h 127.0.0.1 -p '$HAPROXY_WRITE_PORT' -U postgres -d postgres -Atq"; }
prepare_patroni_cert() { local pki="$ETCD_RUNTIME/pki"; [[ -s $pki/ca.key && -s $pki/ca.crt ]] || { echo 'M3 runtime CA missing; run etcd-configure first' >&2; exit 1; }; [[ -s $HA_RUNTIME/patroni-etcd.crt ]] && return; umask 077; openssl genrsa -out "$HA_RUNTIME/patroni-etcd.key" 2048 >/dev/null 2>&1; openssl req -new -key "$HA_RUNTIME/patroni-etcd.key" -subj '/CN=pgsentry-m4-patroni' -out "$HA_RUNTIME/patroni-etcd.csr"; printf 'extendedKeyUsage=clientAuth\n' >"$HA_RUNTIME/patroni-etcd.ext"; openssl x509 -req -in "$HA_RUNTIME/patroni-etcd.csr" -CA "$pki/ca.crt" -CAkey "$pki/ca.key" -CAcreateserial -days 825 -sha256 -extfile "$HA_RUNTIME/patroni-etcd.ext" -out "$HA_RUNTIME/patroni-etcd.crt" >/dev/null 2>&1; }
