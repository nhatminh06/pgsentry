# M10 observability, alerting, and operations

M10 turns M1–M9 reliability semantics into metrics, alerts, dashboards, and runbooks. Prometheus 3.13.1 and Alertmanager 0.33.1 run on loopback on `control-01` with seven-day retention; authenticated Grafana OSS 13.1.3 is subnet-restricted. node_exporter 1.12.1 runs on all seven VMs. Patroni 4.1.5 `/metrics`, etcd 3.7.1 native metrics over mutual TLS, and HAProxy 2.8.16’s native exporter are scraped directly.

A small 15-second textfile collector publishes writable-primary count, streaming replicas, maximum replay lag in bytes, healthy etcd members, writable HAProxy backends, latest full-backup timestamp, last archive timestamp, and cumulative archive failures. PostgreSQL uses a generated `pgsentry_monitor` login granted only `pg_monitor`; etcd uses a dedicated generated client certificate. Credentials remain ignored under `.pgsentry/`.

```bash
make observability-configure PROFILE=full
make observability-check PROFILE=full
make observability-verify PROFILE=full
make observability-alert-test PROFILE=full ALERT_TEST=replica-loss
```

Verification is non-destructive. Alert tests are explicitly destructive and self-restoring: they select a replica, stop one etcd member, stop only HAProxy, or pause one replica’s replay while generating bounded WAL. Evidence is ignored under `.pgsentry/results/m10/`.

The 24-hour backup-age and 15% filesystem-free thresholds are lab policies. Byte lag is an LSN difference, not seconds. Archive alerting detects a counter increase rather than alerting forever on historical failures. A young backup does not prove recovery; M9 restore/PITR evidence does.

Monitoring is not highly available. `control-01` remains a lab consolidation point for routing, backup, and monitoring. Prometheus does not participate in HA. M10 does not prove a monitoring SLA, 24/7 paging, perfect thresholds, production capacity, HA routing/monitoring, arbitrary failure detection, off-site recovery, or long soak reliability.
