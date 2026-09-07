#!/usr/bin/env bash
set -euo pipefail
source /etc/pgsentry-monitor.env
out=$(mktemp)
trap 'rm -f "$out"' EXIT
primary=0 replicas=0 lag=0 archive_fail=0 archive_last=0 connections=0 commits=0 rollbacks=0 locks=0 db_size=0 long_tx=0
leader=
for ip in 192.168.130.11 192.168.130.12 192.168.130.13; do
  role=$(curl -fsS --max-time 3 "http://$ip:8008/metrics" 2>/dev/null | awk '/^patroni_primary[{ ]/{print $NF; exit}' || true)
  [[ $role == 1 ]] && { primary=$((primary + 1)); leader=$ip; }
done
if [[ -n $leader ]]; then
  sql=$(PGPASSWORD="$PGPASSWORD" psql -h "$leader" -U pgsentry_monitor -d postgres -AtF '|' -c "SELECT count(*) FILTER (WHERE state='streaming'),coalesce(max(pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn)),0)::bigint FROM pg_stat_replication; SELECT failed_count,coalesce(extract(epoch from last_archived_time),0)::bigint FROM pg_stat_archiver; SELECT (SELECT count(*) FROM pg_stat_activity),coalesce(sum(xact_commit),0),coalesce(sum(xact_rollback),0),(SELECT count(*) FROM pg_locks WHERE NOT granted),coalesce(sum(pg_database_size(datname)),0),(SELECT count(*) FROM pg_stat_activity WHERE xact_start < clock_timestamp()-interval '5 minutes') FROM pg_stat_database" 2>/dev/null || true)
  replicas=$(sed -n '1s/|.*//p' <<<"$sql"); lag=$(sed -n '1s/.*|//p' <<<"$sql")
  archive_fail=$(sed -n '2s/|.*//p' <<<"$sql"); archive_last=$(sed -n '2s/.*|//p' <<<"$sql")
  IFS='|' read -r connections commits rollbacks locks db_size long_tx <<<"$(sed -n '3p' <<<"$sql")"
fi
etcd_healthy=0
for endpoint in 192.168.130.21 192.168.130.22 192.168.130.23; do
  curl -fsS --max-time 3 --cacert /etc/prometheus/pki/etcd-ca.crt --cert /etc/prometheus/pki/etcd-monitor.crt --key /etc/prometheus/pki/etcd-monitor.key "https://$endpoint:2379/health" 2>/dev/null | jq -e '.health=="true" or .health==true' >/dev/null && etcd_healthy=$((etcd_healthy + 1)) || true
done
writable=$(printf 'show stat\n' | socat - UNIX-CONNECT:/run/haproxy/admin.sock 2>/dev/null | awk -F, '$1=="patroni_primary" && $2!="BACKEND" && $18=="UP"{n++} END{print n+0}')
backup_ts=0
if command -v pgbackrest >/dev/null && sudo -u postgres pgbackrest --stanza=pgsentry info --output=json >/tmp/pgsentry-backup.json 2>/dev/null; then
  backup_ts=$(jq '[.[0].backup[]?|select(.type=="full")|.timestamp.stop]|max//0' /tmp/pgsentry-backup.json)
  rm -f /tmp/pgsentry-backup.json
fi
cat >"$out" <<EOF
# HELP pgsentry_postgresql_primary_count Writable Patroni primary count.
# TYPE pgsentry_postgresql_primary_count gauge
pgsentry_postgresql_primary_count $primary
# HELP pgsentry_postgresql_replica_count Streaming replicas reported by the primary.
# TYPE pgsentry_postgresql_replica_count gauge
pgsentry_postgresql_replica_count ${replicas:-0}
# HELP pgsentry_replication_lag_bytes Maximum primary-to-replica replay LSN difference in bytes.
# TYPE pgsentry_replication_lag_bytes gauge
pgsentry_replication_lag_bytes ${lag:-0}
# HELP pgsentry_etcd_healthy_members Healthy etcd endpoints out of three.
# TYPE pgsentry_etcd_healthy_members gauge
pgsentry_etcd_healthy_members $etcd_healthy
# HELP pgsentry_haproxy_writable_backends UP servers in the HAProxy write backend.
# TYPE pgsentry_haproxy_writable_backends gauge
pgsentry_haproxy_writable_backends ${writable:-0}
# HELP pgsentry_wal_archive_failures_total PostgreSQL cumulative archive failures.
# TYPE pgsentry_wal_archive_failures_total counter
pgsentry_wal_archive_failures_total ${archive_fail:-0}
# HELP pgsentry_wal_last_success_timestamp_seconds Last successful WAL archive Unix timestamp.
# TYPE pgsentry_wal_last_success_timestamp_seconds gauge
pgsentry_wal_last_success_timestamp_seconds ${archive_last:-0}
# HELP pgsentry_backup_last_success_timestamp_seconds Latest successful full-backup stop timestamp.
# TYPE pgsentry_backup_last_success_timestamp_seconds gauge
pgsentry_backup_last_success_timestamp_seconds $backup_ts
# HELP pgsentry_postgresql_connections Current sessions across connectable databases.
# TYPE pgsentry_postgresql_connections gauge
pgsentry_postgresql_connections ${connections:-0}
# HELP pgsentry_postgresql_commits_total Transactions committed since statistics reset.
# TYPE pgsentry_postgresql_commits_total counter
pgsentry_postgresql_commits_total ${commits:-0}
# HELP pgsentry_postgresql_rollbacks_total Transactions rolled back since statistics reset.
# TYPE pgsentry_postgresql_rollbacks_total counter
pgsentry_postgresql_rollbacks_total ${rollbacks:-0}
# HELP pgsentry_postgresql_waiting_locks Current ungranted locks.
# TYPE pgsentry_postgresql_waiting_locks gauge
pgsentry_postgresql_waiting_locks ${locks:-0}
# HELP pgsentry_postgresql_database_size_bytes Total size of connectable databases.
# TYPE pgsentry_postgresql_database_size_bytes gauge
pgsentry_postgresql_database_size_bytes ${db_size:-0}
# HELP pgsentry_postgresql_long_transactions Transactions open longer than five minutes.
# TYPE pgsentry_postgresql_long_transactions gauge
pgsentry_postgresql_long_transactions ${long_tx:-0}
EOF
chmod 0644 "$out"
chown node_exporter:node_exporter "$out"
mv "$out" /var/lib/node_exporter/textfile/pgsentry.prom
