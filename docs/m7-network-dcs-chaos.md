# M7 network partitions and DCS chaos

## Scope and invariant

M7 extends M5's single leader-to-DCS isolation into a bounded matrix while preserving the central invariant: never more than one writable PostgreSQL primary. The continuous sequenced workload still connects only to HAProxy on `control-01:5000`; direct node connections are observation-only.

The accepted scenarios are:

- `primary-dcs-isolation`: block the current database leader's TCP 2379 traffic to every etcd member. Patroni should demote a leader that cannot prove DCS ownership, then the remaining members may elect safely.
- `replica-dcs-isolation`: isolate one replica from etcd while its WAL path remains intact. It must not promote itself or create a second writable primary.
- `dcs-quorum-loss`: stop two dynamically chosen etcd members, leaving 1/3. Linearizable DCS progress is impossible; Patroni may sacrifice writes until quorum returns.
- `etcd-leader-peer-isolation`: isolate the dynamically discovered etcd leader from both peers on TCP 2380. The connected majority should elect a replacement while the isolated member cannot form quorum alone.
- `replication-partition`: block both replicas' TCP 5432 connections to the current leader while DCS and HAProxy remain available. In async mode the leader may continue acknowledging writes, illustrating a durability exposure rather than a consensus failure.

## Network hygiene

Rules are inserted only on project guests, match exact source/destination addresses and TCP ports, and carry the `pgsentry-m7-chaos` comment. SSH remains available. Cleanup deletes the same rules and restarts intentionally stopped services. A pre/post gate rejects stale rules.

## Evidence

Each run records the fault, target, monotonic injection time, workload outcomes, acknowledged-row retention, role observations, maximum writable-primary count, leadership/routing state, and final topology. An observed interruption is a laboratory measurement rather than guaranteed RTO. Zero observed acknowledged-row loss is not proof of RPO=0.

## Boundaries

M7 does not claim safety for arbitrary partitions, packet corruption, delay/reordering, Byzantine nodes, multi-site failure, storage corruption, etcd disaster recovery, HAProxy redundancy, application retry correctness, a production SLA, guaranteed RTO, or universal RPO=0. Backup, WAL archiving, restore, and PITR remain M9.
