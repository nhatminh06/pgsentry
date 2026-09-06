# pgsentry

pgsentry is a PostgreSQL reliability engineering lab that measures and verifies database behavior under failover, partitions, unsafe migrations, and recovery — rather than merely demonstrating that an HA stack can be deployed.

It is an evidence-producing reliability lab, not a generic PostgreSQL deployment, Kubernetes demo, Patroni showcase, Terraform showcase, unrelated DevOps toolkit, or consensus implementation.

## Status and roadmap

M1 provides VM infrastructure, M2 demonstrates manual PostgreSQL replication, M3 proves independent etcd quorum, M4 integrates Patroni-managed PostgreSQL with HAProxy, and M5 adds repeatable client-visible failure experiments. M6 compares asynchronous and synchronous durability policies.

| Milestone | Capability | Status |
| --- | --- | --- |
| M1 | Terraform infrastructure | Implemented and verified |
| M2 | Manual PostgreSQL streaming replication | Implemented; canonical runtime verified |
| M3 | etcd quorum | Implemented and verified |
| M4 | Patroni HA and HAProxy routing | Implemented and verified |
| M5 | Automated failure and durability harness | Implemented and verified |
| M6 | Synchronous durability experiments | Implemented and verified |
| M7 | Network-partition and DCS chaos | Planned |
| M8 | pgsafe migration safety CLI | Planned |
| M9 | Backup, WAL, and PITR verification | Planned |
| M10 | Observability, runbooks, and portfolio polish | Planned |

## Topologies

The canonical `full` profile creates seven VMs: three PostgreSQL-role nodes, three etcd-role nodes, and a dedicated control node. Later M5–M9 measurements published as project evidence must use this topology.

The `colocated` profile creates three development VMs. Each can later host PostgreSQL, Patroni, and etcd, but results from this resource-constrained topology are not canonical evidence.

See [the architecture](docs/architecture.md) for the separation and network rationale.

## Prerequisites

- Terraform 1.8 or newer
- Linux with KVM, libvirt, and a running system libvirt daemon
- The `default` libvirt storage pool
- An OpenSSH public key for cloud-init access
- Capacity for either three development VMs or seven canonical VMs

The provider downloads the configured Ubuntu cloud image during the first apply. No credentials or private keys belong in Terraform variables or state.

## Infrastructure quick start

```bash
cp terraform/environments/colocated/terraform.tfvars.example \
  terraform/environments/colocated/terraform.tfvars
make tf-validate
make cluster-up PROFILE=colocated
```

Inspect the `ssh_targets` output, then connect with the configured SSH user. Remove the profile with:

```bash
make cluster-down PROFILE=colocated
```

Use `PROFILE=full` only on a host sized for all seven canonical VMs. Terraform state and local variable files are ignored by Git.

## M2 quick start

M2 uses Ubuntu 24.04's PostgreSQL 16 packages. Configuration is performed over SSH after Terraform finishes, keeping guest service configuration out of the infrastructure modules. For canonical evidence:

```bash
make cluster-up PROFILE=full
make pg-configure PROFILE=full
make pg-verify PROFILE=full
make pg-failover PROFILE=full   # destructive: stops pg-01 and promotes pg-02
make cluster-down PROFILE=full
```

Set `PGSENTRY_SSH_KEY` if the private key is not `~/.ssh/id_ed25519`. The replication password is generated at runtime under ignored `.pgsentry/`, is never committed, and is removed by `cluster-down` or `make pg-clean`.

`pg-verify` is non-destructive to cluster roles: it verifies roles, both streaming connections, replicated data, standby write protection, and restart/reconnect behavior. `pg-failover` is deliberately separate and clearly destructive. See [the M2 runbook](docs/m2-postgresql.md) for inspection commands and split-brain precautions.

## M3 quick start

M3 pins etcd and etcdctl v3.7.1 and generates runtime-only TLS credentials. On a provisioned profile:

```bash
make etcd-configure PROFILE=full
make etcd-verify PROFILE=full
make etcd-quorum-test PROFILE=full # destructive but self-restoring
```

The quorum test dynamically stops the elected leader, proves two-member availability, demonstrates one-member quorum loss with bounded operations, restores the members, and verifies persistence across a controlled full service restart. See [the M3 runbook](docs/m3-etcd.md).

## M4 quick start

On a fresh environment, configure etcd first, then Patroni and HAProxy:

```bash
make etcd-configure PROFILE=full
make patroni-configure PROFILE=full
make patroni-verify PROFILE=full
make haproxy-configure PROFILE=full
make haproxy-verify PROFILE=full
make patroni-failover-test PROFILE=full # destructive, self-restoring
```

Patroni owns PostgreSQL once M4 is configured; do not run the M2 `pg-*` configuration targets on the same live data directories. See [the M4 runbook](docs/m4-patroni-haproxy.md).

## M5 quick start

After the full M4 stack passes verification:

```bash
make failure-baseline PROFILE=full
make failure-scenario PROFILE=full SCENARIO=primary-service-loss
make failure-matrix PROFILE=full
make failure-report
```

The destructive scenarios are individually named, restore their failure state, and store machine-readable evidence under ignored `.pgsentry/results/m5/`. See [the M5 runbook](docs/m5-failure-testing.md).

## M6 quick start

M6 reuses the M5 client and failure analysis while changing Patroni's cluster-wide durability policy:

```bash
make durability-set PROFILE=full MODE=sync
make durability-verify PROFILE=full MODE=sync
make durability-latency PROFILE=full MODE=sync
make durability-failure-test PROFILE=full MODE=sync TRIAL=1 # destructive, self-restoring
make durability-report
```

The default after experiments is restored to `async`. Strict mode deliberately blocks bounded client writes when no synchronous standby exists. See [the M6 runbook](docs/m6-synchronous-durability.md).
