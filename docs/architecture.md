# pgsentry architecture

## Topology boundaries

The canonical topology uses seven VMs: three PostgreSQL-role nodes, three etcd-role nodes, and one control node. PostgreSQL and etcd are separated so database failure experiments do not implicitly remove DCS members, and DCS experiments do not implicitly remove database processes. That separation makes later observations attributable to the failure being injected.

The control VM is also separate. Workload generation, client-visible measurements, HAProxy, and fault injection will eventually run there so the observer and injector remain alive when a database or etcd target is deliberately stopped. M1 provisions only the host and its network attachment.

The three-node `colocated` profile reduces laptop cost by allowing PostgreSQL, Patroni, and etcd to share each node in later milestones. It is useful for development, but only the `full` profile may produce canonical M5–M9 evidence.

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

## Later CI architecture

```text
GitHub-hosted PR CI
    -> Go tests, lint, Terraform validation, static pgsafe checks

Self-hosted reliability CI with real VM access
    -> chaos tests, runtime migration tests, backup restore, PITR
```

This is future architecture, not M1 functionality. No CI workflows or later milestone tools are implemented here.

## M2 PostgreSQL boundary

The canonical M2 cluster uses PostgreSQL only on `pg-01`, `pg-02`, and `pg-03`. The etcd and control VMs remain service-free in this milestone. The development `colocated` profile can run the same logical PostgreSQL cluster on `node-01`, `node-02`, and `node-03`, but only the full profile provides canonical evidence.

M2 uses native asynchronous physical streaming replication. It deliberately does not introduce etcd, Patroni, HAProxy, automatic failover, or client routing. Guest configuration is applied after Terraform over SSH so infrastructure lifecycle and PostgreSQL lifecycle remain separate.

## M3 etcd boundary

M3 configures `etcd-01`, `etcd-02`, and `etcd-03` as an independent three-voter Raft cluster. Client traffic on TCP 2379 and peer traffic on TCP 2380 use mutual TLS. PostgreSQL does not consume the cluster yet. Terraform continues to own only VMs, disks, and networks; SSH-driven scripts own runtime PKI and guest services.

The colocated development profile maps the logical members to `node-01`, `node-02`, and `node-03`. Canonical evidence uses the separated full-profile addresses `192.168.130.21` through `.23`.
