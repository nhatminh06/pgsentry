# Consolidated evidence

Evidence is bounded to canonical lab runs. A successful finite trial is not a universal production guarantee.

| Area | Measured or asserted evidence | Milestone |
| --- | --- | --- |
| Infrastructure | Seven deterministic VMs booted, accepted SSH, and destroyed with zero Terraform resources | M1 |
| Replication | Exactly one primary, two streaming read-only replicas, replicated marker, restart/reconnect | M2 |
| DCS | Three mutual-TLS etcd voters; 2/3 retained quorum and 1/3 could not commit | M3 |
| HA/routing | Patroni promotion and HAProxy rerouting to exactly one `/primary` backend | M4 |
| Failure behavior | Sequenced client outcomes, interruptions, ambiguity, direct writer count, retained acknowledgements | M5 |
| Durability | Async/sync/sync-strict trials; strict writes blocked without an eligible synchronous standby | M6 |
| Partitions | DCS/WAL partitions with maximum writable-primary count asserted at one | M7 |
| Migrations | PostgreSQL 16 AST fixtures plus bounded real lock and replication demonstrations | M8 |
| Recovery | 23,436,968-byte full backup in 6,499 ms; latest and PITR restores around 2.5 s; deleted row recovered | M9 |
| Operations | 15 targets, semantic metrics, three Git dashboards, and four live alert lifecycles | M10 |

M9 used backup `20260907-021333F`: latest recovery included post-backup data, and named PITR retained a row before its exact DELETE while excluding a post-target marker. No acknowledged-row loss and no multiple-writer state were observed in accepted finite M5–M7 trials; those observations do not establish universal RPO=0 or arbitrary-partition safety. M10 observes their signals but does not replace failure testing.
