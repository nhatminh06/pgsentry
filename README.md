# pgsentry

pgsentry is a PostgreSQL reliability engineering lab that measures and verifies database behavior under failover, partitions, unsafe migrations, and recovery — rather than merely demonstrating that an HA stack can be deployed.

It is an evidence-producing reliability lab, not a generic PostgreSQL deployment, Kubernetes demo, Patroni showcase, Terraform showcase, unrelated DevOps toolkit, or consensus implementation.

## Status and roadmap

M1 implements only the VM and network infrastructure. PostgreSQL and the reliability experiments are planned, not yet implemented.

| Milestone | Capability | Status |
| --- | --- | --- |
| M1 | Terraform infrastructure | Implemented; provisioning evidence pending |
| M2 | Manual PostgreSQL streaming replication | Planned |
| M3 | etcd quorum | Planned |
| M4 | Patroni HA and HAProxy routing | Planned |
| M5 | Automated failover harness | Planned |
| M6 | Synchronous durability experiments | Planned |
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

## M1 quick start

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

