# Operations index

Use this entry point for an already-provisioned canonical `full` environment.

| Question | Command |
| --- | --- |
| Patroni topology | `make patroni-verify PROFILE=full` |
| Current primary | `curl -s http://192.168.130.11:8008/cluster \| jq '.members[]|select(.role=="leader" or .role=="primary")'` |
| Replication | `SELECT * FROM pg_stat_replication;` on the primary |
| etcd quorum | `make etcd-verify PROFILE=full` |
| HAProxy route | `make haproxy-verify PROFILE=full` |
| Backup inventory | `make backup-info PROFILE=full` |
| WAL archive | `make backup-archive-verify PROFILE=full` |
| Monitoring | `make observability-check PROFILE=full && make observability-verify PROFILE=full` |
| Active alerts | `ssh pgsentry@192.168.130.31 'curl -s http://127.0.0.1:9090/api/v1/alerts' \| jq .` |
| Grafana | `ssh -L 3000:192.168.130.31:3000 pgsentry@192.168.130.31`, then `http://127.0.0.1:3000` |

The generated Grafana password is stored with mode 0600 under `.pgsentry/ha/`. Alert procedures are under [runbooks](runbooks/); start with [no primary](runbooks/no-primary.md), [multiple primaries](runbooks/multiple-primaries.md), or [etcd quorum](runbooks/etcd-quorum.md).

Safe final teardown order:

```bash
make observability-clean PROFILE=full
make backup-clean PROFILE=full
make cluster-down PROFILE=full
```

The last two commands permanently remove backup/WAL data and VMs. Preserve accepted evidence first. Never delete PGDATA, etcd data, DCS keys, or archived WAL as an ad-hoc response.
