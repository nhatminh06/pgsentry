# M2 PostgreSQL streaming replication and manual failover

## Scope

M2 demonstrates PostgreSQL 16's native physical replication and manual promotion on real Ubuntu 24.04 VMs. It exposes the mechanics that later Patroni and etcd milestones will automate. It does not provide automatic leader election, fencing, routing, or a zero-loss guarantee.

The canonical full-profile topology begins as:

```text
                 asynchronous WAL
pg-01 PRIMARY  -------------------->  pg-02 STANDBY
      |
      +---------------------------->  pg-03 STANDBY
                 asynchronous WAL
```

The colocated profile maps the same logical roles to `node-01`, `node-02`, and `node-03` for development only.

## Configuration and bootstrap

Run `make pg-configure PROFILE=full` after the VMs are reachable. The SSH-driven configuration scripts install Ubuntu's PostgreSQL 16 packages, configure `pg-01`, and initialize each standby with `pg_basebackup --write-recovery-conf`. Physical replication slots named `pg_02` and `pg_03` prevent required WAL from being removed while a replica is temporarily disconnected.

Important primary settings are:

- `listen_addresses = '*'`: accepts connections on the private libvirt network; `pg_hba.conf` still controls access.
- `wal_level = replica`: writes the WAL information physical standbys need.
- `max_wal_senders = 10`: leaves bounded headroom above the two expected senders for base backup and inspection.
- `max_replication_slots = 10`: supports the two physical slots with bounded lab headroom.
- `hot_standby = on`: permits read-only queries while recovery applies WAL.
- a subnet-scoped `host replication` rule using SCRAM authentication: only topology members can authenticate as the runtime-created replication role.

The replication credential is randomly generated into `.pgsentry/replication-password` with restrictive permissions. It is copied only to PostgreSQL's protected `.pgpass` files and never belongs in Terraform, Git, or documentation.

Guests need outbound package access through libvirt NAT. On hosts where UFW uses a default-deny routed policy, permit only the active project subnet from the libvirt bridge to the host's real egress interface. For example, the canonical test host required:

```bash
sudo ufw route allow in on virbr1 out on enp3s0 from 192.168.130.0/24
```

Interface names are host-specific; diagnose UFW logs rather than copying them blindly. The canonical run showed blocked `IN=virbr1 OUT=enp3s0 SRC=192.168.130.11` TCP traffic before this rule and successful package downloads afterward.

Healthy reruns do not rebuild a standby that is already in recovery and following the intended upstream. A standby whose upstream changes during failover is explicitly and destructively re-bootstrapped.

## Inspecting the initial cluster

```bash
ssh pgsentry@192.168.130.11 \
  "sudo -u postgres psql -c 'SELECT pg_is_in_recovery();'"

ssh pgsentry@192.168.130.11 \
  "sudo -u postgres psql -c \"SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication ORDER BY application_name;\""

ssh pgsentry@192.168.130.12 \
  "sudo -u postgres psql -c 'SELECT status, sender_host, latest_end_lsn FROM pg_stat_wal_receiver;'"

ssh pgsentry@192.168.130.13 \
  "sudo -u postgres psql -c 'SELECT status, sender_host, latest_end_lsn FROM pg_stat_wal_receiver;'"
```

`make pg-verify PROFILE=full` additionally writes a unique evidence row, observes it on both standbys, proves a standby rejects writes, restarts all three PostgreSQL services, and waits for both replicas to stream again. It does not change roles.

## Manual failover

`make pg-failover PROFILE=full` is intentionally destructive and performs these explicit steps:

1. Re-run the initial replication proof and write a unique pre-failover row.
2. Confirm both standbys received that row.
3. Stop PostgreSQL and mask its service units on `pg-01`.
4. Confirm the old primary is unavailable.
5. Promote `pg-02` with `pg_ctlcluster 16 main promote`.
6. Prove `pg-02` is no longer in recovery and accepts writes.
7. Re-bootstrap `pg-03` from `pg-02` using a new physical slot.
8. Write a unique post-failover row on `pg-02` and observe it on `pg-03`.

The resulting topology is:

```text
pg-01 STOPPED AND MASKED

                 asynchronous WAL
pg-02 PRIMARY  -------------------->  pg-03 STANDBY
```

## Former-primary safety

Promotion creates a new timeline. Starting the unchanged `pg-01` while `pg-02` is writable would create two independent primaries: split brain. The failover script therefore leaves `pg-01` stopped and masks its PostgreSQL service units. It does not claim that `pg-01` is a standby.

Rejoining it safely requires explicit reconciliation, normally `pg_rewind` when prerequisites and retained WAL permit it, or a destructive fresh base backup from `pg-02`. That rejoin is not automated in M2.

## Durability limitation

Replication is asynchronous. A successful controlled run may observe every test row on the promoted standby, but transactions acknowledged by the old primary before reaching `pg-02` can be lost. M2 neither measures RPO nor proves RPO=0. Synchronous durability experiments belong to a later milestone.

## Cleanup

Destroy the profile with `make cluster-down PROFILE=full`. This also deletes the local runtime credential. Do not retain VM disks, Terraform state, database directories, or `.pgsentry/` contents in Git.
