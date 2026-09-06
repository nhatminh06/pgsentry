# M5 failure injection and client-visible evidence

## Harness

M5 runs a bounded Python workload from the libvirt host through only `control-01:5000`. Every operation receives a run ID and monotonic sequence number. Shell drivers gate each fault on full cluster health, discover roles dynamically, inject one failure dimension, restore it with a cleanup trap, assert final health, and write JSON evidence beneath ignored `.pgsentry/results/m5/`. The report generator derives its table and repeated-trial statistics from those files.

An observed client write interruption is the monotonic interval between the last confirmed successful write before injection and the first confirmed successful write afterward. A confirmed success is an operation for which `psql` returned success. A confirmed failure is known not to have returned success. An ambiguous outcome is a timeout or lost connection after submission where the client cannot know whether commit occurred. Ambiguous sequence IDs are retried unchanged; a duplicate-key response demonstrates that the earlier attempt committed.

Acknowledged-row loss compares every confirmed committed sequence with rows present after recovery. Zero missing rows means only that no acknowledged loss was observed in that trial. PostgreSQL remains asynchronous and this is not an RPO=0 claim. Timings are laboratory observations, not guaranteed RTO or an SLA.

## Failure models

- `primary-service-loss`: stops Patroni on the dynamically discovered primary.
- `primary-vm-loss`: abruptly powers off that VM with `virsh destroy`, preserving its disk and Terraform state.
- `replica-loss`: stops Patroni on a dynamically selected replica.
- `etcd-member-loss`: stops one etcd member while quorum remains.
- `primary-dcs-isolation`: adds tagged guest-local OUTPUT rules blocking only the leader's TCP 2379 traffic to the three etcd addresses. SSH, WAL, REST, HAProxy, and etcd peer traffic remain available. Timestamped direct-SQL role samples enforce the no-two-writable-primary invariant. Exact tagged rules are removed afterward.
- `haproxy-loss`: stops the single HAProxy process without disturbing the database cluster.

A safe distributed system may sacrifice write availability when authoritative leadership cannot be proven. HAProxy controls routing, not consensus. Its loss demonstrates that database HA does not provide routing-layer HA: the database can remain healthy while the sole client endpoint is unavailable.

## Running

```bash
make failure-baseline PROFILE=full
make failure-scenario PROFILE=full SCENARIO=replica-loss
make failure-matrix PROFILE=full
make failure-report
```

Every scenario restores its stopped service, VM, or firewall rule and requires a full healthy baseline afterward. Result JSON contains no connection string or credential. Existing PostgreSQL connections cannot migrate; the workload reconnects to the same HAProxy address for each attempt.

## Boundaries and M6

M5 does not prove guaranteed RTO, production SLA, RPO=0, arbitrary-partition correctness, synchronous durability, HAProxy redundancy, backup/restore, PITR, etcd disaster recovery, multi-site availability, or application retry correctness. M6 can reuse the workload, result schema, retention comparison, and reporting while changing the durability policy explicitly.
