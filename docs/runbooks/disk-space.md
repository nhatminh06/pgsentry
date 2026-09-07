# Disk space low

## Meaning and impact

`PgSentryDiskSpaceLow` means a monitored non-temporary filesystem has less than 15% available for five minutes. The threshold is a lab policy, not universal capacity planning. Determine whether PostgreSQL PGDATA, WAL, or the control-node backup repository is affected.

```bash
df -hT
sudo du -xhd1 /var/lib/postgresql /var/lib/pgbackrest /var/lib/prometheus 2>/dev/null
sudo journalctl --disk-usage
```

Identify the current PostgreSQL leader and avoid changes that could remove required WAL or backups. Check replication slots, pgBackRest retention, logs, Prometheus retention, and unexpected files. Use reviewed retention/cleanup procedures; do not delete PGDATA, `pg_wal`, etcd data, or backup files manually. Verify free capacity stabilizes, PostgreSQL writes succeed, replicas stream, archival succeeds, and backup inventory remains OK. Escalate if safe reclamation cannot stay ahead of growth. See [M9](../m9-backup-pitr.md).
