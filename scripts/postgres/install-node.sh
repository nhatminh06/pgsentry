#!/usr/bin/env bash
set -euo pipefail

if ! dpkg-query -W -f='${Status}\n' postgresql-16 postgresql-client-16 2>/dev/null | grep -q 'install ok installed'; then
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-client-16
fi
sudo systemctl enable postgresql
