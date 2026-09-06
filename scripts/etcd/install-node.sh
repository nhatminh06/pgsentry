#!/usr/bin/env bash
set -euo pipefail
version=$1 checksum=$2
archive="etcd-$version-linux-amd64.tar.gz"
if [[ $(etcd --version 2>/dev/null | awk 'NR==1{print $3}') != "${version#v}" ]]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 "https://github.com/etcd-io/etcd/releases/download/$version/$archive" -o "$tmp/$archive"
  echo "$checksum  $tmp/$archive" | sha256sum -c -
  tar -xzf "$tmp/$archive" -C "$tmp"
  sudo install -m 0755 "$tmp/etcd-$version-linux-amd64/etcd" "$tmp/etcd-$version-linux-amd64/etcdctl" /usr/local/bin/
fi
id etcd >/dev/null 2>&1 || sudo useradd --system --home /var/lib/etcd --shell /usr/sbin/nologin etcd
sudo install -d -o etcd -g etcd -m 700 /var/lib/etcd
sudo install -d -o root -g etcd -m 750 /etc/etcd /etc/etcd/pki
