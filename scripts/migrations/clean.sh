#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../durability/common.sh"; profile=${1:-full}; durability_load "$profile"; leader=$(leader_name); password=$(runtime_secret superuser-password); ip=$(name_ip "$leader")
ssh_node "$ip" "PGPASSWORD='$password' psql -h '$ip' -U postgres -d postgres -v ON_ERROR_STOP=1 -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name LIKE 'pgsafe-m8%' AND pid<>pg_backend_pid(); DROP SCHEMA IF EXISTS pgsafe_m8 CASCADE;\""
