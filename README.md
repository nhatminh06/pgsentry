# PgSentry

PgSentry is a PostgreSQL reliability engineering lab that verifies high availability, failure behavior, migration safety, durability, historical recovery, and operational alerting with reproducible evidence.

## Why PgSentry

Deploying an HA stack does not show what clients experience during failure, whether a partition creates two writers, whether acknowledged data survives, whether a migration blocks traffic, or whether a backup can restore history. PgSentry turns those questions into bounded experiments with explicit safety assertions and machine-readable evidence.

## Architecture

```text
clients -> HAProxy :5000 -> Patroni PostgreSQL pg-01/02/03
                              | physical WAL replication
                              v
                         etcd-01/02/03

all seven VMs + PostgreSQL + Patroni + etcd + HAProxy + pgBackRest
                              |
                              v
                 Prometheus -> Alertmanager -> runbooks
                              |
                              v
                           Grafana

PostgreSQL -> full backup + archived WAL -> control-01 repository
                                               |
                                               v
                                  isolated restore / named PITR
```

Prometheus observes the system; it never participates in leader election or routing. `control-01` consolidates routing, backup storage, and monitoring to fit a laptop lab. That is not a production colocation recommendation. See [the complete architecture](docs/architecture.md).

## What it demonstrates

| Capability | Verified behavior | Evidence |
| --- | --- | --- |
| Infrastructure | Seven deterministic libvirt VMs provision and destroy | M1 |
| Replication | One primary and two read-only streaming replicas | M2 |
| Consensus | Three-member mutual-TLS etcd quorum and bounded failures | M3 |
| Database HA | Patroni promotion and HAProxy role-aware routing | M4 |
| Failure measurement | Client interruption, ambiguity, retained acknowledgements | M5 |
| Durability | Async, sync, and sync-strict policy tradeoffs | M6 |
| Partition safety | Bounded DCS/WAL partitions with writer-count assertions | M7 |
| Migration safety | PostgreSQL 16 AST analysis and real lock demonstrations | M8 |
| Historical recovery | Full backup, post-backup WAL replay, named-target PITR | M9 |
| Operations | Semantic metrics, alerts, Git dashboards, and runbooks | M10 |

The [evidence matrix](docs/evidence.md) separates measured observations from broader claims.

## Reliability findings

- HAProxy provides a stable write endpoint, but existing sessions still require retry/reconnect behavior after failover.
- No acknowledged-row loss was observed in finite M5/M6 trials; this is not a universal RPO=0 guarantee.
- Sync-strict mode blocked bounded writes when no eligible synchronous standby existed.
- M7 directly sampled every database member and observed no more than one writable primary in its bounded matrix.
- Replication copied an intentional DELETE to both replicas. M9 PITR reconstructed the deleted row from backup plus archived WAL.
- M10 requires real replica, etcd-member, HAProxy, and replay-lag alerts to fire in Prometheus/Alertmanager and resolve after recovery.

## Migration safety

`pgsafe` is a read-only Go CLI using the PostgreSQL 16 parser AST. It flags dangerous locks, rewrites, destructive statements, transaction-incompatible operations, and missing timeout policy without connecting to a database.

```bash
make pgsafe-build
./bin/pgsafe check migration.sql --format=json --fail-on=high
./bin/pgsafe explain PGSAFE001
```

See [the guide](docs/m8-pgsafe.md) and [rule catalog](docs/pgsafe-rules.md).

## Backup and recovery

pgBackRest stores full physical backups and archived WAL on `control-01`. M9 proved that a latest restore included a post-backup marker and named-target PITR restored a row that replication had deleted everywhere. A successful or young backup is not equivalent to a proven restore. See [M9](docs/m9-backup-pitr.md).

## Observability

Prometheus scrapes node_exporter on all seven VMs plus native Patroni, etcd mTLS, and HAProxy endpoints. A small collector publishes stable primary-count, replica-count, byte-lag, DCS, routing, backup-age, and archive-failure metrics. Alertmanager records local alert lifecycle, Grafana is provisioned from Git, and every alert points to a [runbook](docs/runbooks/).

## Quick start

The canonical path requires Linux/KVM, libvirt, Terraform 1.8+, the `default` libvirt pool, an SSH key, and capacity for seven Ubuntu 24.04 VMs.

```bash
cp terraform/environments/full/terraform.tfvars.example terraform/environments/full/terraform.tfvars
make tf-validate
make cluster-up PROFILE=full
make etcd-configure PROFILE=full
make patroni-configure PROFILE=full
make haproxy-configure PROFILE=full
make backup-configure PROFILE=full
make backup-full PROFILE=full
make observability-configure PROFILE=full
make observability-verify PROFILE=full
```

Use [operations](docs/operations.md) for inspection and teardown or [the demo](docs/demo.md) for a concise walkthrough.

## Repository structure

| Path | Purpose |
| --- | --- |
| `terraform/` | Canonical and development libvirt topology |
| `scripts/` | Service lifecycle and bounded reliability experiments |
| `monitoring/` | Prometheus rules/configuration and Grafana assets |
| `cmd/pgsafe`, `internal/pgsafe` | Migration-safety CLI |
| `docs/runbooks/` | Alert response procedures |
| `docs/` | Architecture, evidence, operations, demo, and deep dives |

## Security model

Services are limited to private libvirt subnets. etcd retains mutual TLS. PostgreSQL monitoring uses a dedicated `pg_monitor` login. Grafana requires a generated administrator password. Secrets exist only under ignored `.pgsentry/`; runtime databases, TSDBs, backup data, WAL, images, and Terraform state are not committed.

## Limitations

PgSentry is a finite single-host lab, not production-ready infrastructure. It does not prove a production SLA, universal RTO/RPO, perfect alerts, long-duration capacity, off-site/immutable backup, geographic DR, HA monitoring/routing, zero false positives/negatives, or correctness under arbitrary failures.

## Design decisions and deep dives

[Architecture](docs/architecture.md) · [Evidence](docs/evidence.md) · [Operations](docs/operations.md) · [Demo](docs/demo.md) · [M5 failures](docs/m5-failure-testing.md) · [M6 durability](docs/m6-synchronous-durability.md) · [M7 partitions](docs/m7-network-dcs-chaos.md) · [M8 migrations](docs/m8-pgsafe.md) · [M9 recovery](docs/m9-backup-pitr.md) · [M10 observability](docs/m10-observability.md)

## Roadmap

| Milestone | Capability | Status |
| --- | --- | --- |
| M1 | Terraform/libvirt infrastructure | Complete |
| M2 | PostgreSQL physical replication | Complete |
| M3 | Independent etcd quorum | Complete |
| M4 | Patroni HA and HAProxy routing | Complete |
| M5 | Failure and durability evidence harness | Complete |
| M6 | Synchronous durability experiments | Complete |
| M7 | Network-partition and DCS chaos | Complete |
| M8 | pgsafe migration-safety CLI | Complete |
| M9 | Backup, WAL, and PITR verification | Complete |
| M10 | Observability, runbooks, and portfolio polish | Complete |

Planned project roadmap complete. Optional future work—off-site storage, HA routing/monitoring, geographic DR, self-hosted reliability CI, and longer soak tests—is outside the completed roadmap.
