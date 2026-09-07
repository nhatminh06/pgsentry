# pgsafe rule catalog

The CLI's `pgsafe rules` and `pgsafe explain` commands are authoritative for the pinned release. Diagnostics are conservative operational signals; suppress only one rule on the following statement with an explicit reason.

| ID | Severity | Operation | Why it matters | Safer approach |
| --- | --- | --- | --- | --- |
| PGSAFE001 | HIGH | CREATE INDEX | A regular build can block table writes. | Consider CONCURRENTLY outside a transaction. |
| PGSAFE002 | HIGH | DROP INDEX | A regular drop requires a strong table lock. | Use CONCURRENTLY where PostgreSQL permits. |
| PGSAFE003 | HIGH | concurrent index in transaction | PostgreSQL rejects this combination. | Disable runner transaction wrapping. |
| PGSAFE004 | HIGH | ALTER COLUMN TYPE | May rewrite data/rebuild indexes under strong locks. | Expand, backfill, and contract for large live tables. |
| PGSAFE005 | HIGH | SET NOT NULL | May scan existing rows under a strong lock. | Prove with a staged valid CHECK first. |
| PGSAFE006 | HIGH | immediate CHECK | Existing rows are validated immediately. | Add NOT VALID, then validate separately. |
| PGSAFE007 | WARNING | VALIDATE CONSTRAINT | Scans rows with non-zero locking and runtime cost. | Run as a monitored, bounded step. |
| PGSAFE008 | HIGH | immediate foreign key | Validation affects referencing and referenced tables. | Add NOT VALID, then validate separately. |
| PGSAFE009 | CRITICAL | DROP table/schema/database | Destructive and potentially strongly locking. | Deprecate first; use reviewed recovery planning. |
| PGSAFE010 | CRITICAL | TRUNCATE | Removes all rows and takes ACCESS EXCLUSIVE locks. | Use reviewed bounded retention/deletion. |
| PGSAFE011 | CRITICAL | DELETE without WHERE | Can delete every row. | Add a reviewed predicate and batch large work. |
| PGSAFE012 | HIGH | UPDATE without WHERE | Rewrites every row version, generating locks, WAL, and bloat. | Add a predicate and batch large work. |
| PGSAFE013 | CRITICAL | DROP COLUMN | Destructive ALTER TABLE with strong locking. | Remove dependencies and defer cleanup. |
| PGSAFE014 | HIGH | CLUSTER/VACUUM FULL/non-concurrent REINDEX | Can block access or rewrite substantial storage. | Prefer concurrent forms or maintenance windows. |
| PGSAFE015 | WARNING | lock-heavy DDL without lock_timeout | Lock acquisition can wait indefinitely. | Set a non-zero lock_timeout; separately choose statement_timeout. |
| PGSAFE016 | HIGH | volatile ADD COLUMN default | PostgreSQL 16 cannot use the fast-default optimization for volatile expressions. | Add, batch-backfill, then set the default. |

False positives are possible because the analyzer intentionally does not know whether a relation is empty, tiny, temporary, or already inside an approved maintenance window. Those facts belong in an auditable statement-scoped suppression reason, not an invisible global exemption.
