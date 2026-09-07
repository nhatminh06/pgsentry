# Backup stale

## Meaning and impact

`PgSentryBackupStale` means the latest successful full backup is older than the lab’s 24-hour threshold. This policy is demonstrative; a young backup does not prove recoverability. Confirm archive continuity and repository integrity.

```bash
make backup-info PROFILE=full
make backup-check PROFILE=full
make backup-full PROFILE=full
```

Inspect pgBackRest JSON inventory, job logs, repository mounts, capacity, and the current Patroni leader. Address scheduling, repository, or database connectivity before taking a reviewed full backup. Do not expire the only valid backup, delete archived WAL, or interpret job success as restore proof. Recovery requires an OK stanza, a current full backup, healthy archival, and separately retained M9 restore/PITR evidence. Escalate if inventory is corrupt or WAL continuity is uncertain. See [M9](../m9-backup-pitr.md) and [archive failure](wal-archive-failure.md).
