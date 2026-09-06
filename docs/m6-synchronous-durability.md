# M6 synchronous durability experiments

## Policies and semantics

M6 applies policy through Patroni's dynamic DCS configuration. It never edits `synchronous_standby_names` behind Patroni's back.

- `async`: `synchronous_mode=off`, `synchronous_mode_strict=false`, and `synchronous_commit=on`. With no `synchronous_standby_names`, `on` waits for local WAL flush only.
- `sync`: `synchronous_mode=on`, strict mode off, and `synchronous_node_count=1`. Patroni selects one synchronous standby and may disable the requirement temporarily if none is eligible, favoring availability.
- `sync-strict`: synchronous mode on, strict mode on, and one required synchronous node. Patroni retains a synchronous requirement when no candidate is available, so commits block until a standby returns.

PostgreSQL `synchronous_commit=on` waits for local durability and for the required standby to flush WAL to durable storage. `remote_write` waits only for a write to the standby operating system, while `remote_apply` additionally waits for WAL replay and query visibility. M6 uses `on`; `remote_apply` is not part of the mandatory matrix. `pg_stat_replication.sync_state` reports `sync`, `potential`, or `async`, and `sync_priority` describes priority-based selection.

## Commands

```bash
make durability-set PROFILE=full MODE=async
make durability-verify PROFILE=full MODE=async
make durability-latency PROFILE=full MODE=async

make durability-set PROFILE=full MODE=sync
make durability-verify PROFILE=full MODE=sync
make durability-failure-test PROFILE=full MODE=sync TRIAL=1
make durability-standby-loss PROFILE=full

make durability-set PROFILE=full MODE=sync-strict
make durability-verify PROFILE=full MODE=sync-strict
make durability-strict-test PROFILE=full

make durability-matrix PROFILE=full
make durability-report
```

All normal writes use the unchanged HAProxy endpoint. Policy verification checks Patroni's live dynamic configuration, PostgreSQL's live settings, and `pg_stat_replication`; configuration text alone is not accepted as evidence. Result JSON and the generated report are stored beneath ignored `.pgsentry/results/m6/`.

## Experiments and safety

The matrix measures healthy-path commit latency under every policy, performs three fresh abrupt-primary-loss trials in both async and sync modes, removes the dynamically selected synchronous standby in non-strict mode, and removes both replicas in strict mode while keeping the primary, DCS, HAProxy, and client alive. The strict workload uses bounded statement and process timeouts. Cleanup traps restore every stopped VM or Patroni service, and each experiment ends with policy and topology verification.

Synchronous mode restricts automatic promotion to candidates Patroni considers safe according to its DCS synchronous state. That is stronger than asynchronous operation, but guarantees still depend on the setting active at commit time, the selected standby's state, surviving storage, DCS availability, Patroni behavior, and the tested failure model. Simultaneous storage loss, operator misconfiguration, and arbitrary partitions remain outside the guarantee boundary. PostgreSQL changes can become visible locally if a backend is cancelled while waiting for synchronous acknowledgement; an ambiguous retry may therefore encounter a duplicate key after a standby returns even though the original client never received success.

No missing acknowledged row in finite trials means only that no acknowledged-row loss was observed. It does not prove universal RPO=0, guaranteed RTO, a production SLA, backup correctness, PITR, etcd disaster recovery, multi-site durability, or application retry correctness.

## Final policy

The matrix restores `async` after all experiments. This preserves the pre-M6 default for later milestones rather than silently changing the cluster's normal availability policy.
