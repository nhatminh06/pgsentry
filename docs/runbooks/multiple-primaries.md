# Multiple writable primaries

## Meaning and impact

`PgSentryMultiplePrimaries` is a critical safety incident: direct SQL observations indicate more than one writable PostgreSQL node. Availability is secondary to preventing divergent writes.

## Safety-first response

1. Stop application writes at the client/load-balancer boundary where possible.
2. Record Prometheus alerts, Patroni `/cluster`, direct `pg_is_in_recovery()` results, timelines, LSNs, and etcd endpoint status.
3. Determine which member owns the Patroni leader key and whether etcd has quorum.
4. Do not manually promote any node and do not write to either suspected primary.
5. Isolate or stop the writer that does not own safe leadership, using the narrowest reviewed fencing action.

```bash
ssh pgsentry@192.168.130.11 'sudo /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list -f json'
for ip in 192.168.130.11 192.168.130.12 192.168.130.13; do ssh pgsentry@$ip "sudo -u postgres psql -Atc 'select pg_is_in_recovery(),timeline_id from pg_control_checkpoint()'"; done
make etcd-verify PROFILE=full
```

Inspect `journalctl -u patroni` and M7 partition state before mitigation. Never “restart everything,” delete DCS keys, or discard PGDATA as a first response. Resume traffic only after exactly one writer, coherent DCS ownership, two streaming replicas, and HAProxy routing are verified. Preserve divergent data for reconciliation. Escalate immediately if the safe writer cannot be established. See [M7 evidence](../m7-network-dcs-chaos.md).
