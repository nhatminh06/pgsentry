#!/usr/bin/env bash
set -euo pipefail
version=$1
sudo env DEBIAN_FRONTEND=noninteractive apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-client-16 python3-venv python3-dev libpq-dev gcc
if [[ ! -x /opt/patroni/bin/patroni ]] || [[ $(/opt/patroni/bin/patroni --version 2>/dev/null | awk '{print $2}') != "$version" ]]; then
  sudo python3 -m venv /opt/patroni
  sudo /opt/patroni/bin/pip install --disable-pip-version-check "patroni[etcd3]==$version" psycopg2-binary
fi
sudo systemctl disable --now postgresql || true
sudo systemctl mask postgresql.service postgresql@16-main.service
sudo install -d -o postgres -g postgres -m 700 /var/lib/postgresql/16
sudo install -d -o root -g postgres -m 750 /etc/patroni /etc/patroni/pki
