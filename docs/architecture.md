# pgsentry architecture

## Topology boundaries

The canonical topology uses seven VMs: three PostgreSQL-role nodes, three etcd-role nodes, and one control node. PostgreSQL and etcd are separated so database failure experiments do not implicitly remove DCS members, and DCS experiments do not implicitly remove database processes. That separation makes later observations attributable to the failure being injected.

The control VM is also separate. Workload generation, client-visible measurements, HAProxy, and fault injection will eventually run there so the observer and injector remain alive when a database or etcd target is deliberately stopped. M1 provisions only the host and its network attachment.

The three-node `colocated` profile reduces laptop cost by allowing PostgreSQL, Patroni, and etcd to share each node. It is useful for development, but only the `full` profile may produce canonical M5–M10 evidence.

## Network model

Each profile receives its own libvirt NAT network with deterministic DHCP reservations. The network is reachable from the libvirt host for SSH administration and permits communication among topology members. NAT permits guests to retrieve packages without exposing guest service ports directly to external networks.

| Source | Destination | Purpose | Future ports |
| --- | --- | --- | --- |
| libvirt host | all nodes | administration | SSH 22 |
| PostgreSQL nodes | PostgreSQL nodes | replication | PostgreSQL 5432 |
| PostgreSQL/Patroni nodes | etcd nodes | DCS client traffic | etcd 2379 |
| etcd nodes | etcd nodes | DCS peer traffic | etcd 2380 |
| control | PostgreSQL/Patroni nodes | workload, health checks, fault control | 22, 5432, 8008 |
| control | etcd nodes | observation and fault control | 22, 2379 |

M1 does not open these ports to `0.0.0.0/0` or install services. Guest-level, role-specific firewall rules belong to the milestone that owns each service, when its bind addresses and operational requirements exist.

## Final system architecture

```text
Client -> control-01 HAProxy -> Patroni PostgreSQL pg-01/02/03
                                      | physical WAL
                                      v
                              etcd-01/02/03 (mTLS)

all seven hosts + native service endpoints
                  |
                  v
      control-01 Prometheus (observer)
           /                 \
   Alertmanager             Grafana
        |
     runbooks

PostgreSQL -> backup + WAL -> control-01 pgBackRest -> isolated restore/PITR
```

Prometheus and Alertmanager observe state but never participate in DCS leadership, PostgreSQL promotion, or HAProxy routing. `control-01` consolidates routing, backup, and monitoring to bound lab cost; this failure-domain colocation is not a production recommendation.

## CI architecture

```text
GitHub-hosted PR CI
    -> Go tests, lint, Terraform validation, static pgsafe checks

Local or future self-hosted reliability CI with real VM access
    -> chaos, runtime migration, backup/PITR, monitoring alert lifecycle
```

Hosted CI validates source, Terraform, monitoring rules, Alertmanager configuration, dashboards, and runbook links. It does not claim seven-VM runtime acceptance. No permanently pending self-hosted workflow is configured.

## M2 PostgreSQL boundary

The canonical M2 cluster uses PostgreSQL only on `pg-01`, `pg-02`, and `pg-03`. The etcd and control VMs remain service-free in this milestone. The development `colocated` profile can run the same logical PostgreSQL cluster on `node-01`, `node-02`, and `node-03`, but only the full profile provides canonical evidence.

M2 uses native asynchronous physical streaming replication. It deliberately does not introduce etcd, Patroni, HAProxy, automatic failover, or client routing. Guest configuration is applied after Terraform over SSH so infrastructure lifecycle and PostgreSQL lifecycle remain separate.

## M3 etcd boundary

M3 configures `etcd-01`, `etcd-02`, and `etcd-03` as an independent three-voter Raft cluster. Client traffic on TCP 2379 and peer traffic on TCP 2380 use mutual TLS. PostgreSQL does not consume the cluster yet. Terraform continues to own only VMs, disks, and networks; SSH-driven scripts own runtime PKI and guest services.

The colocated development profile maps the logical members to `node-01`, `node-02`, and `node-03`. Canonical evidence uses the separated full-profile addresses `192.168.130.21` through `.23`.

## M4 integrated HA boundary

M4 places Patroni above PostgreSQL on the three `pg-*` nodes. Patroni uses a dedicated client certificate to coordinate through the M3 etcd cluster. The native PostgreSQL systemd service is masked: systemd owns Patroni, and Patroni exclusively owns PostgreSQL. HAProxy on `control-01` exposes port 5000 and uses each Patroni REST `/primary` endpoint on port 8008 to admit exactly one writable backend.

HAProxy changes routing for new TCP connections after a role change. Existing PostgreSQL sessions cannot migrate and applications still require reconnect/retry behavior. M4 tests one controlled primary loss and one etcd-member loss, not the broader failure matrix reserved for M5.

## M5 reliability harness boundary

M5 adds a host-side continuous client, scenario-specific fault injection, direct role observation, structured JSON results, and generated comparison reports. Normal writes always use `control-01:5000`; direct node access is reserved for assertions and recovery. Each experiment gates on and restores the healthy M4 topology before another begins.

The targeted DCS experiment blocks only the current database leader's etcd client traffic. The harness samples every PostgreSQL role and treats more than one writable primary as a safety failure. HAProxy loss is measured separately because the single routing node remains a client-access SPOF even while the database tier is healthy.

## M6 synchronous durability boundary

M6 leaves the seven-VM topology and stable HAProxy client path unchanged. It changes Patroni's dynamic cluster configuration among `async`, `sync`, and `sync-strict`, while Patroni remains the sole owner of `synchronous_standby_names` and synchronous failover eligibility. PostgreSQL uses `synchronous_commit=on`: a synchronous acknowledgement waits for the selected standby to flush WAL, not replay it.

The same M5 sequenced workload measures healthy commit latency, failure interruption, ambiguous outcomes, and retained acknowledged rows. Non-strict synchronous mode may favor availability when no eligible synchronous standby exists; strict mode preserves the synchronous requirement and can therefore block writes. M6 is controlled evidence, not a universal zero-RPO guarantee.

## M7 partition and DCS-chaos boundary

M7 keeps the canonical topology, Patroni ownership, etcd mutual TLS, async default, and stable HAProxy write path. It introduces one bounded failure dimension at a time: DCS isolation of a database member, loss of etcd quorum, peer isolation of the elected etcd leader, or interruption of both replica WAL connections. Tagged guest-local firewall rules preserve SSH and unrelated ports and are removed exactly by cleanup traps.

Direct SQL observations sample all database members throughout each fault. More than one writable PostgreSQL node is an immediate safety failure. These controlled partitions do not model arbitrary packet loss, delay, reordering, Byzantine behavior, or every asymmetric topology.

## M8 migration-safety boundary

`pgsafe` is a standalone, read-only Go CLI. SQL flows through the PostgreSQL 16 `libpg_query` parser, its AST is evaluated by deterministic rules, and diagnostics are rendered as text or JSON. The CLI has no database driver or execution path. GitHub-hosted CI runs only static build, test, fixture, and Terraform checks.

Selected lock demonstrations are separate shell automation for the canonical full topology. They use a disposable `pgsafe_m8` schema, bounded PostgreSQL timeouts, the existing HAProxy client path, and ignored evidence under `.pgsentry/results/m8/`. Patroni continues to own PostgreSQL; M8 does not inject node, DCS, or network failures.

## M9 backup and historical-recovery boundary

M9 mounts a restricted NFSv4 pgBackRest repository physically hosted at `control-01:/var/lib/pgbackrest` on each Patroni member. Patroni's dynamic PostgreSQL configuration owns `archive_mode`, `archive_command`, and restart semantics; systemd still owns Patroni, and Patroni still owns every live PostgreSQL process. Backups dynamically use the current leader.

Latest-state and PITR restores run outside Patroni on control-01 in fresh `/var/lib/pgbackrest-restore/*` directories. They bind only `127.0.0.1:55432`, use explicit `pg_ctl` lifecycle, never join the DCS, and never enter HAProxy. This off-PGDATA repository is operational separation inside one lab network, not geographic disaster recovery.

## M10 observability and operations boundary

Prometheus and Alertmanager run loopback-only on `control-01`; authenticated Grafana is reachable only through the lab network/host path. node_exporter runs on all seven VMs. Prometheus scrapes Patroni, HAProxy, and etcd native metrics without weakening mutual TLS. A dedicated `pg_monitor` login and etcd client certificate are generated at runtime.

A minimal collector publishes cross-component semantics: writable-primary count, streaming replicas, byte replay lag, healthy etcd members, writable HAProxy backends, backup age, and archive failures. These feed actionable rules, Git-provisioned dashboards, and runbooks. Monitoring remains outside the HA control plane.
