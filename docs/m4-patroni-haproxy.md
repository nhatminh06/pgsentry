# M4 Patroni PostgreSQL HA and HAProxy routing

## Components and ownership

PostgreSQL replicates database WAL. etcd stores distributed coordination state. Patroni controls PostgreSQL roles and process lifecycle. HAProxy provides clients a stable primary endpoint.

```text
client -> control-01:5000 HAProxy -> current Patroni primary
                                      |-- WAL --> replica
                                      `-- WAL --> replica

pg-01/02/03 Patroni -> mutually authenticated TLS -> etcd-01/02/03
```

Patroni 4.1.5 is pinned in `scripts/ha/common.sh` and installed with its `etcd3` extra into `/opt/patroni`, a dedicated Python virtual environment. Ubuntu supplies PostgreSQL 16 and HAProxy. The native `postgresql.service` and `postgresql@16-main.service` are disabled and masked. systemd owns `patroni.service`; Patroni alone starts and stops PostgreSQL under `/var/lib/postgresql/16/patroni`.

M2 remains the manual educational foundation. M4 performs a fresh Patroni bootstrap rather than converting M2 data in place. Never run M2 `pg-configure`, `pg-verify`, or `pg-failover` against nodes currently managed by Patroni.

## DCS and TLS

Patroni uses the dedicated namespace `/pgsentry/m4/`, scope `pgsentry`, and all three etcd v3 endpoints. A runtime-only Patroni client certificate is signed by M3's runtime CA and deployed with its key to the PostgreSQL nodes. CA validation and mutual client authentication remain enabled; no insecure TLS bypass is used. Patroni stores initialization, configuration, leader-lock, and member state under its namespace. Those keys are inspected read-only and must not be edited manually.

## PostgreSQL bootstrap and rewind

The first Patroni member acquires the DCS initialize/leader locks and creates a checksummed PostgreSQL cluster. The other nodes clone it using `pg_basebackup`. Bootstrap enables `wal_log_hints`, physical slots, asynchronous streaming, and `use_pg_rewind`. Checksums and WAL hints allow `pg_rewind` to reconcile blocks changed on a former primary after timelines diverge. Automation preserves an existing healthy data directory and fails if data exists without its managed configuration.

## HAProxy routing

HAProxy listens on `control-01:5000`. Its static backend contains all three PostgreSQL addresses, but it checks port 8008 with `GET /primary`; only the Patroni primary returns HTTP 200 and becomes eligible. A TCP-only port 5432 check would be unsafe because replicas accept database connections too.

During failover the backend list does not change. Patroni promotes an eligible replica, its REST role response changes, and HAProxy directs new connections to it. Existing TCP sessions are not migrated; clients must reconnect and retry transactions safely.

## Controlled test

`make patroni-failover-test PROFILE=full` discovers the leader dynamically and stops only that node's Patroni service. No `patronictl failover` or manual PostgreSQL promotion is issued. It waits boundedly for automatic promotion, reconnects through the same HAProxy endpoint, writes a post-failover marker, restarts the former primary, verifies its replica role and catch-up, then stops one etcd member and proves 2/3 DCS quorum preserves database and routing availability. Cleanup traps attempt to restart intentionally stopped services.

All waits and client operations are bounded. Any printed elapsed seconds are one-run observations, not guaranteed RTO. Replication is asynchronous, so M4 does not prove RPO=0.

## Boundaries

M4 does not prove arbitrary partitions, etcd quorum-loss behavior, a broad failure matrix, synchronous durability, guaranteed RTO/RPO, backup restore, PITR, multi-site HA, or application retry correctness. Those belong to later milestones.
