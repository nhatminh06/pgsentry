#!/usr/bin/env bash
set -euo pipefail

PGSENTRY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PGSENTRY_SSH_KEY=${PGSENTRY_SSH_KEY:-$HOME/.ssh/id_ed25519}
PGSENTRY_SSH_USER=${PGSENTRY_SSH_USER:-pgsentry}
PGSENTRY_RUNTIME="$PGSENTRY_ROOT/.pgsentry"

load_profile() {
  mkdir -p "$PGSENTRY_RUNTIME"
  chmod 700 "$PGSENTRY_RUNTIME"
  case "${1:-}" in
    full)
      PG_PRIMARY=192.168.130.11
      PG_STANDBY_ONE=192.168.130.12
      PG_STANDBY_TWO=192.168.130.13
      PG_SUBNET=192.168.130.0/24
      ;;
    colocated)
      PG_PRIMARY=192.168.131.11
      PG_STANDBY_ONE=192.168.131.12
      PG_STANDBY_TWO=192.168.131.13
      PG_SUBNET=192.168.131.0/24
      ;;
    *)
      echo "profile must be 'full' or 'colocated'" >&2
      exit 2
      ;;
  esac
}

ssh_node() {
  ssh -i "$PGSENTRY_SSH_KEY" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$PGSENTRY_RUNTIME/known_hosts" \
    "$PGSENTRY_SSH_USER@$1" "${@:2}"
}

wait_for_ssh() {
  local address=$1
  local attempt
  for attempt in $(seq 1 30); do
    if ssh_node "$address" true 2>/dev/null; then
      return
    fi
    sleep 5
  done
  echo "SSH did not become ready on $address" >&2
  return 1
}

wait_for_query() {
  local address=$1
  local query=$2
  local expected=$3
  local attempt result
  for attempt in $(seq 1 30); do
    result=$(run_query "$address" "$query" 2>/dev/null || true)
    if [[ $result == "$expected" ]]; then
      return
    fi
    sleep 2
  done
  echo "query on $address did not return expected value '$expected' (last: '$result')" >&2
  return 1
}

run_query() {
  local address=$1
  local query=$2
  local encoded_query
  encoded_query=$(printf %s "$query" | base64 -w 0)
  ssh_node "$address" "printf %s $encoded_query | base64 -d | sudo -u postgres psql -Atq"
}

runtime_password() {
  local password_file="$PGSENTRY_RUNTIME/replication-password"
  mkdir -p "$PGSENTRY_RUNTIME"
  chmod 700 "$PGSENTRY_RUNTIME"
  if [[ ! -s $password_file ]]; then
    umask 077
    openssl rand -hex 32 >"$password_file"
  fi
  cat "$password_file"
}

run_remote_script() {
  local address=$1
  local script=$2
  shift 2
  ssh -i "$PGSENTRY_SSH_KEY" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$PGSENTRY_RUNTIME/known_hosts" \
    "$PGSENTRY_SSH_USER@$address" "bash -s -- $*" <"$script"
}

run_remote_script_with_input() {
  local address=$1
  local script=$2
  local remote_script="/tmp/pgsentry-$(basename "$script")"
  local encoded_script
  shift 2
  encoded_script=$(base64 -w 0 "$script")
  ssh_node "$address" \
    "printf %s $encoded_script | base64 -d >$remote_script; bash $remote_script $*; status=\$?; rm -f $remote_script; exit \$status"
}
