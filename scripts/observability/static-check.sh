#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=
cleanup() { [[ -n $tmp ]] && rm -rf "$tmp"; }
trap cleanup EXIT
promtool=${PROMTOOL:-promtool}; amtool=${AMTOOL:-amtool}
if ! command -v "$promtool" >/dev/null || ! command -v "$amtool" >/dev/null; then
  tmp=$(mktemp -d)
  curl -fsSL https://github.com/prometheus/prometheus/releases/download/v3.13.1/prometheus-3.13.1.linux-amd64.tar.gz -o "$tmp/prometheus.tgz"
  echo '962b812371aff838d152b6ff2d56fdb7a6396f5542f48ebf73421b9721f0d103  '"$tmp/prometheus.tgz" | sha256sum -c -
  tar -xzf "$tmp/prometheus.tgz" -C "$tmp"
  curl -fsSL https://github.com/prometheus/alertmanager/releases/download/v0.33.1/alertmanager-0.33.1.linux-amd64.tar.gz -o "$tmp/alertmanager.tgz"
  echo '93d802cba6a8d27239d747ce117df7648d326ab67394e32247540b030e9842ba  '"$tmp/alertmanager.tgz" | sha256sum -c -
  tar -xzf "$tmp/alertmanager.tgz" -C "$tmp"
  promtool="$tmp/prometheus-3.13.1.linux-amd64/promtool"
  amtool="$tmp/alertmanager-0.33.1.linux-amd64/amtool"
fi
rendered="$tmp/prometheus.yml"
[[ -n $tmp ]] || { tmp=$(mktemp -d); rendered="$tmp/prometheus.yml"; }
openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=static-check -keyout "$tmp/check.key" -out "$tmp/check.crt" -days 1 >/dev/null 2>&1
sed -e "s|/etc/prometheus/rules.yml|$root/monitoring/prometheus/rules.yml|" \
  -e "s|/etc/prometheus/pki/etcd-ca.crt|$tmp/check.crt|" \
  -e "s|/etc/prometheus/pki/etcd-monitor.crt|$tmp/check.crt|" \
  -e "s|/etc/prometheus/pki/etcd-monitor.key|$tmp/check.key|" \
  "$root/monitoring/prometheus/prometheus.yml" >"$rendered"
"$promtool" check config "$rendered"
"$promtool" check rules "$root/monitoring/prometheus/rules.yml"
"$amtool" check-config "$root/monitoring/alertmanager/alertmanager.yml"
find "$root/monitoring/grafana/dashboards" -name '*.json' -print0 | xargs -0 -n1 jq empty
grep -Rho 'runbook: docs/runbooks/[^ }]*' "$root/monitoring/prometheus/rules.yml" | awk '{print $2}' | while read -r file; do test -s "$root/$file" || { echo "missing runbook: $file" >&2; exit 1; }; done
