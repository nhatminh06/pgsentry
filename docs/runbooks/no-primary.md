# No writable primary

## Meaning and impact

`PgSentryNoPrimary` means no Patroni member reports ownership of the leader lock and writable PostgreSQL. New writes fail. The immediate safety question is whether every node is truly read-only; do not promote until DCS state is understood.

## First response

```bash
make patroni-verify PROFILE=full
ssh pgsentry@192.168.130.11 'sudo /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list'
curl -s http://192.168.130.11:8008/cluster | jq .
```

Check `systemctl status patroni`, `journalctl -u patroni --since -15m`, PostgreSQL recovery state, and etcd health on all members. Likely causes are DCS quorum loss, a failed leader, failed promotion, or PostgreSQL startup failure.

Restore etcd quorum or the failed service before considering a reviewed Patroni failover. Do not run `pg_ctl promote`, delete DCS keys, remove PGDATA, or promote multiple nodes. Recovery requires one Patroni leader, two streaming replicas, one writable HAProxy backend, and a successful routed write. Escalate if role observations disagree or quorum cannot be restored. See [M4](../m4-patroni-haproxy.md), [etcd quorum](etcd-quorum.md), and [multiple primaries](multiple-primaries.md).
