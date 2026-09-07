# etcd member or quorum failure

## Meaning and impact

`PgSentryEtcdMemberDown` means fewer than 3/3 members respond; 2/3 is degraded but retains quorum. `PgSentryEtcdQuorumLost` means fewer than 2/3 respond; 1/3 cannot commit new consensus state. Patroni may reduce availability intentionally rather than risk unsafe leadership.

```bash
make etcd-verify PROFILE=full
. scripts/etcd/common.sh; load_profile full; etcdctl_cmd endpoint status --cluster -w table
ssh pgsentry@192.168.130.21 'systemctl status etcd; journalctl -u etcd --since -15m'
```

Identify the elected leader and failed member, then restore only the known member’s service, disk, TLS, or connectivity. Confirm the database has at most one writer. Do not casually create a new cluster, use `--force-new-cluster`, delete member data, or remove DCS keys. Recovery requires 3/3 healthy endpoints, one etcd leader, coherent Patroni membership, and one PostgreSQL primary. Escalate if member identity/data disagree or quorum cannot be restored. See [M3](../m3-etcd.md) and [M7](../m7-network-dcs-chaos.md).
