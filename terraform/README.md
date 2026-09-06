# Terraform infrastructure

The environments use the `dmacvicar/libvirt` provider against a local system libvirt daemon. Both profiles share small network and VM modules. Environment maps define exact topology, addresses, and resource sizes.

Copy an example to `terraform.tfvars`, set a real SSH public-key path, and use the root Makefile. The `full` environment is the canonical seven-node evidence environment; `colocated` is development-only.

Terraform owns only networks, disks, and VMs. PostgreSQL guest configuration is intentionally performed by the root Makefile's `pg-*` targets after provisioning; see `docs/m2-postgresql.md`.
