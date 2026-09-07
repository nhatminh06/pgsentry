# PgSentry 10–20 minute demo

This path assumes the canonical stack is configured and avoids the long destructive matrices.

1. Run `make patroni-verify PROFILE=full` and `make observability-verify PROFILE=full`.
2. Open the provisioned **PgSentry Overview** dashboard using the tunnel in [operations](operations.md). Show one primary, two replicas, three etcd members, one writable backend, backup age, and alerts.
3. Run `make haproxy-verify PROFILE=full` to prove the client route.
4. Run `make observability-alert-test PROFILE=full ALERT_TEST=replica-loss`. Show the firing `PgSentryReplicaCountLow`, its runbook annotation, and resolution.
5. Run `make pgsafe-build` then `./bin/pgsafe check testdata/migrations/unsafe/risky.sql`.
6. Show `make backup-info PROFILE=full` and [M9 recovery evidence](m9-backup-pitr.md); do not rerun full PITR for a short demo.
7. Finish with `make observability-verify PROFILE=full` and `make patroni-verify PROFILE=full`.

For deeper demonstrations use [M5](m5-failure-testing.md), [M7](m7-network-dcs-chaos.md), [M8](m8-pgsafe.md), or [M9](m9-backup-pitr.md).
