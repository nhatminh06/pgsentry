# M1 architecture

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

