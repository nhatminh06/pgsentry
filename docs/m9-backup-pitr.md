# M9 physical backup, WAL archive, restore, and PITR

## Reliability question and architecture

Streaming replication copies current physical state, including operator mistakes. M9 answers a separate question: can an earlier database state be reconstructed after every live member has faithfully replayed a destructive transaction?

```text
Patroni PostgreSQL (dynamic leader)
        |  physical full backup + continuous WAL
        v
control-01:/var/lib/pgbackrest
        |
        v
isolated 127.0.0.1:55432 recovery instance
```

Ubuntu 24.04's exact `pgbackrest=2.50-1build2` package is installed on the three database nodes and control-01. It supports PostgreSQL 16 and supplies physical backup, `archive-push`, `archive-get`, inventory, integrity checks, and target recovery. The POSIX repository is NFS-exported only to the full topology subnet, maps clients to control-01's unprivileged `postgres` identity, is owned by `postgres:postgres` with mode 0750, and is mounted `hard,nosuid,nodev`. It is unencrypted; the private libvirt network and filesystem permissions are lab controls, not an immutable or geographically independent DR system. Two full backups are retained, and archive retention follows full-backup retention. Expiration is not part of acceptance.

## PostgreSQL recovery primitives

WAL records describe physical changes needed for crash recovery and replication. A WAL segment is a bounded file in that stream. A physical base backup captures a consistent recoverable copy of the whole PostgreSQL cluster lineage, not selected table files. A checkpoint makes dirty state durable and bounds recovery work; pgBackRest's fast-start backup requests one.

`archive_mode=on` enables completed-segment archival and requires restart. `archive_command` invokes `pgbackrest --stanza=pgsentry archive-push %p`; success means PostgreSQL may recycle that segment. `pg_stat_archiver` exposes successes, failures, and last segment/timestamps. `pg_switch_wal()` closes the current segment so it can be archived. During restore, pgBackRest writes a `restore_command` using `archive-get`, and PostgreSQL requests the WAL it needs.

A base backup establishes a starting point; archived WAL reconstructs transactions after it. Therefore practical recovery-point capability advances past backup time only while required WAL successfully reaches the archive. It is incorrect to call time since the last full backup the PITR RPO. No single lab run guarantees a production RPO.

`pg_create_restore_point(name)` writes a named WAL record at a server-selected LSN. `recovery_target_name` stops after replay reaches that record; `recovery_target_time` instead compares transaction timestamps and requires careful timezone/timing choices. Promotion ends recovery and may create a new timeline. Failover can also create a timeline; history files identify divergent WAL histories. A physical restore retains the PostgreSQL system identifier/lineage, but it is not a Patroni member: system identity, Patroni scope, and this lab run ID are distinct concepts.

## Configuration and health

Start with a healthy M4 stack in the canonical `full` profile and async M6 policy:

```bash
make backup-configure PROFILE=full
make backup-check PROFILE=full
make backup-info PROFILE=full
```

Configuration is convergent: package version, NFS export/mount, config, retention, and Patroni dynamic settings are reconciled without deleting the stanza or repository. Restart is rolling, replicas first and leader last. A repository reset occurs only through the explicitly destructive `backup-clean` target. Inspect operations with:

```sql
SELECT archived_count, last_archived_wal, last_archived_time,
       failed_count, last_failed_wal, last_failed_time
FROM pg_stat_archiver;
SELECT pg_switch_wal();
```

```bash
make backup-archive-verify PROFILE=full
make backup-info PROFILE=full
```

All commands fail closed. A nonzero archive push increments/fills failure fields and prevents archive verification; `pgbackrest check`, backup, inventory, restore, and SQL assertions must each succeed. Missing required WAL makes recovery fail rather than skip history.

## Full backup, latest restore, and PITR

`make backup-full PROFILE=full` discovers the Patroni leader and records source, label, timestamps, duration, size, version, and system identifier. `backup-info` records pgBackRest's inventory. Generated JSON is under ignored `.pgsentry/results/m9/`.

The complete destructive-but-disposable proof is:

```bash
make backup-acceptance PROFILE=full
```

It inserts marker A through HAProxy, takes the full backup, inserts marker B, and archives WAL. A fresh latest restore must contain A and B, proving B arrived through WAL rather than the base backup. The restore runs on control-01 in `/var/lib/pgbackrest-restore/latest`, binds only `127.0.0.1:55432`, is started with `pg_ctl`, and is promoted after archive recovery.

Next it inserts a protected row, creates a named restore point, inserts a post-target marker, and executes an exact predicate DELETE through HAProxy. Direct observation proves the protected row absent on the leader and both streaming replicas. After forcing and verifying archival, a fresh `/var/lib/pgbackrest-restore/pitr` restore targets the named point. The protected row must exist there and the post-target row must not. This is why HA is not backup: replicas serve the current state; base backup plus archived WAL reconstructs historical state.

`restore-verify` also asserts PostgreSQL recovery completed, the endpoint is loopback/nonstandard, no WAL receiver exists, isolated archiving is disabled, the restore follows the backup's current timeline, the Patroni membership remains three, and HAProxy has no port 55432 backend. Disabling archive-push on the promoted restore prevents its divergent timeline history from contaminating the accepted live archive. Cleanup stops the explicit process and removes recovery PGDATA. The live Patroni cluster is never overwritten.

## Timing and operational limits

The evidence records full-backup size/duration and latest/PITR restore durations. They are observations from small seven-VM lab guests, not a production backup window, RTO, RPO, or SLA. Restore RTO is the time required to obtain backup/WAL, reconstruct, validate, and return a usable service; M9 measures only its isolated lab subset.

M9 does not prove geographic or multi-region DR, immutable/WORM or ransomware-resistant storage, cloud durability, hardware fault tolerance, etcd recovery, full Patroni reconstruction, retention compliance, cross-system application consistency, zero corruption probability, or every PITR target. Off-host or object-storage replication would add failure-domain separation and provider durability, but would require separate credential, encryption, retention, and restore tests.

M8 reduces the chance that hazardous migrations execute; M9 recovers history after destructive state has already been accepted and replicated. Prevention and recovery are complementary, not coupled.
