# Replication lag

## Meaning and impact

`PgSentryReplicationLagHigh` means the maximum primary-to-replica replay LSN difference exceeded 1 MiB for 30 seconds. Units are bytes, not seconds. A standby may say `streaming` while replay is paused or slow; confirm one writable primary before action.

```bash
ssh pgsentry@192.168.130.11 "sudo -u postgres psql -x -c \"select application_name,state,sent_lsn,write_lsn,flush_lsn,replay_lsn,pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn) lag_bytes from pg_stat_replication\""
ssh pgsentry@192.168.130.12 "sudo -u postgres psql -Atc 'select pg_is_wal_replay_paused(),pg_last_wal_replay_lsn()'"
```

Check receiver/replay state, host CPU/disk/network, replication slots, WAL availability, and `journalctl -u patroni`. Resume replay only if it was intentionally paused: `SELECT pg_wal_replay_resume();`. Do not pause both replicas, delete slots, or rebuild a standby before identifying missing WAL or resource pressure. Verify lag returns below threshold and both replicas stream. Escalate if lag grows, required WAL is gone, or synchronous policy threatens write availability. See [M6](../m6-synchronous-durability.md).
