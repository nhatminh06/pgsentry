# Replication degraded

## Meaning and impact

`PgSentryReplicaCountLow` or `PgSentryPatroniMemberDown` means fewer than two streaming replicas or an unavailable Patroni endpoint. The primary may remain writable, but failover choices and durability margin are reduced. Confirm there is still exactly one primary.

```bash
make patroni-verify PROFILE=full
ssh pgsentry@192.168.130.11 'sudo /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list'
ssh pgsentry@192.168.130.11 "sudo -u postgres psql -x -c 'select * from pg_stat_replication'"
```

Inspect the affected member’s `systemctl status patroni`, `journalctl -u patroni`, disk space, network reachability, receiver status, slots, and timelines. Safely restore the stopped service or connectivity and allow Patroni to rejoin it. Do not promote a replica merely because another replica failed; do not delete PGDATA or slots casually. Recovery requires one leader and two streaming replicas with shrinking lag. Escalate on timeline divergence, missing WAL, or repeated reinitialization. See [M2](../m2-postgresql.md) and [replication lag](replication-lag.md).
