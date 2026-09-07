# WAL archive failure

## Meaning and impact

`PgSentryWALArchiveFailure` means PostgreSQL’s cumulative archive failure counter increased during the last five minutes. A cumulative nonzero value alone does not mean a current failure. Continued failure can make recent PITR impossible and fill `pg_wal`; verify the live primary first.

```bash
make backup-check PROFILE=full
make backup-archive-verify PROFILE=full
ssh pgsentry@192.168.130.11 "sudo -u postgres psql -x -c 'select * from pg_stat_archiver'"
ssh pgsentry@192.168.130.11 'sudo -u postgres pgbackrest --stanza=pgsentry check'
```

Inspect `last_failed_wal`, `last_failed_time`, pgBackRest logs, NFS mount health, repository permissions/capacity, and Patroni’s current archive command. Restore repository connectivity or permissions; do not disable archiving, delete unarchived WAL, reset statistics to hide the incident, or rebuild the repository casually. Verify a newly generated segment archives and `failed_count` stops increasing. Escalate if required WAL is missing. See [M9](../m9-backup-pitr.md) and [backup stale](backup-stale.md).
