# M3 etcd quorum, election, and recovery

## Scope and architecture

M3 runs a three-voter etcd Raft cluster independent of PostgreSQL:

```text
etcd-01 192.168.130.21 ─┐
etcd-02 192.168.130.22 ─┼── three-member Raft cluster
etcd-03 192.168.130.23 ─┘
```

The colocated development mapping is `node-01` through `node-03` at `192.168.131.11` through `.13`. The full profile is canonical. PostgreSQL supplies database replication; etcd supplies distributed coordination. Patroni will later use etcd to coordinate which PostgreSQL member may act as leader. etcd does not replicate PostgreSQL data.

etcd and etcdctl are pinned to v3.7.1 with the release archive SHA-256 in `scripts/etcd/common.sh`. This is the current stable upstream release line at implementation time and avoids an unreviewed future `latest` download.

## TLS and configuration

`make etcd-configure PROFILE=full` creates a runtime CA beneath ignored `.pgsentry/etcd/pki`, then creates separate certificates for administrator client access, each client listener, and each peer listener. Node certificates contain the node name and fixed IP SAN. Both client and peer listeners require certificates chaining to the CA; verification is never skipped.

Each member explicitly sets its name, persistent `/var/lib/etcd` data directory, advertised/listening client and peer URLs, full initial membership, state `new`, and a pinned cluster token. Re-running configuration preserves `/var/lib/etcd`; an existing data directory without managed configuration is rejected rather than silently erased. systemd enables and supervises `etcd`. UFW rules are restricted to the profile subnet on TCP 2379 and 2380.

## Quorum and failure model

For three voting members, quorum is two:

```text
3/3 -> available
2/3 -> available
1/3 -> unavailable for consensus writes and linearizable reads
```

A follower failure leaves the leader and quorum intact. A leader failure leaves two voters, which elect a new leader and continue committing. Losing two members leaves no majority; bounded consensus operations fail. A serializable read may still return local state and therefore is not evidence of quorum.

`make etcd-quorum-test PROFILE=full` discovers the leader from endpoint status, stops it, proves a post-failure write, restarts it without deleting persistent Raft state, then stops two members and captures failed write and linearizable-read results. It separately checks a serializable read, restores one member and proves availability, restores all three, and finishes with a persistent-marker/full-service-restart test. Commands use three-second dial and five-second command timeouts. Those bounds prevent hangs; they are not measurements of election or detection latency. A trap attempts to restart every intentionally stopped service after interruption.

## Inspection

After configuration, use the generated client credentials:

```bash
make etcd-verify PROFILE=full
.pgsentry/etcd/etcdctl \
  --endpoints=https://192.168.130.21:2379,https://192.168.130.22:2379,https://192.168.130.23:2379 \
  --cacert=.pgsentry/etcd/pki/ca.crt \
  --cert=.pgsentry/etcd/pki/admin.crt \
  --key=.pgsentry/etcd/pki/admin.key \
  endpoint status --cluster -w table
```

Status exposes each member ID, leader ID, Raft term, committed index, applied index, and database size. A term identifies an election epoch. The Raft index orders committed log entries; applied index records how far the state machine has applied that log.

## Persistence and recovery

A normal stopped member retains its identity and log under `/var/lib/etcd`. Restarting it lets it catch up from its peers. Deleting that directory changes the problem into destructive member replacement and can compromise availability if performed casually. M3 tests restart recovery, not snapshot-based disaster recovery.

## Boundaries

M3 does not add Patroni, HAProxy, PostgreSQL automatic failover, application routing, backup/PITR, multi-site consensus, or PostgreSQL RTO/RPO claims.
