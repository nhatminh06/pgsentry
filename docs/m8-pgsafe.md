# M8 pgsafe migration safety CLI

## Why this exists

A healthy Patroni cluster can still suffer an application outage when DDL queues behind a lock or blocks writes. Patroni handles node leadership; it does not judge migration SQL. `pgsafe` provides a deterministic pre-merge explanation of PostgreSQL 16 operational hazards without connecting to PostgreSQL or executing the migration.

```text
SQL -> PostgreSQL parser -> AST -> rule registry -> diagnostics -> text / JSON
```

The parser is `github.com/pganalyze/pg_query_go/v5` v5.1.0, backed by the PostgreSQL 16 generation of `libpg_query`. It correctly separates comments, quoted identifiers, strings containing semicolons, schema-qualified names, multiline input, and multiple statements. It uses CGO and therefore requires a C compiler at build time; Ubuntu hosted runners provide one. Regular expressions are used only for the auditable suppression comment syntax.

## CLI and policy

- `pgsafe check <file...>` reads only explicit files; `-` reads stdin.
- `--format=text|json` selects human or stable schema-versioned output.
- `--fail-on=info|warning|high|critical` sets the CI threshold; default is `high`.
- `--transaction-mode=single|wrapped` models whether a runner wraps the migration. `wrapped` rejects concurrent index operations.
- `pgsafe rules`, `pgsafe explain RULE_ID`, and `pgsafe version` expose the stable contract.

Exit 0 means no unsuppressed diagnostic meets the threshold, exit 1 means findings meet it, and exit 2 means usage, configuration, I/O, parse, or internal failure. A parse error never reports a migration as safe. Files and diagnostics are sorted by file, statement, then rule ID.

## Suppressions

An exception applies only to the following statement and one explicit rule:

```sql
-- pgsafe: ignore PGSAFE001 reason="small table, approved maintenance window"
CREATE INDEX idx_code ON small_lookup(code);
```

The rule ID and non-empty reason are mandatory. Malformed or unknown suppressions produce exit 2. Suppressed diagnostics remain visible in text and JSON and do not suppress other rules on the statement. There is no global ignore-all switch.

## PostgreSQL 16 decisions and safe patterns

For a live table, prefer `CREATE INDEX CONCURRENTLY` when its longer runtime, two scans, transaction restriction, and possible invalid-index cleanup are acceptable. Stage CHECK and foreign-key constraints with `NOT VALID`, then run `VALIDATE CONSTRAINT`; validation is not lock-free but permits ordinary writes. For NOT NULL, a validated `CHECK (column IS NOT NULL)` can let PostgreSQL avoid a fresh full-table proof. Large type changes often need expand/backfill/contract because static analysis cannot prove binary compatibility or cost.

PostgreSQL 11 and newer can use a missing-value optimization when adding a column with a non-volatile default. `pgsafe` therefore does not repeat old advice that every constant default rewrites the table; it flags known volatile calls such as `clock_timestamp()`, `random()`, and `nextval()`. `lock_timeout` bounds time waiting to acquire a lock, not statement execution. `statement_timeout` bounds execution too, and should not be set unrealistically low for valid long-running concurrent builds or validation.

## Runtime evidence boundary

`make migration-runtime-test PROFILE=full` is deliberately separate from the analyzer. It creates only `pgsafe_m8`, demonstrates a plain index build timing out behind a writer, creates a concurrent index while writes use `control-01:5000`, demonstrates an AccessExclusiveLock ALTER boundary, stages and validates a CHECK, and proves harmless committed DDL appears on all physical replicas. Each operation has bounded timeouts; cleanup terminates only `pgsafe-m8%` sessions and drops only the disposable schema. Evidence is ignored under `.pgsentry/results/m8/`.

Hosted CI never claims this KVM evidence. It runs Go formatting, tests, vet, build, compiled fixture acceptance, and Terraform static validation. Canonical runtime verification remains local/self-hosted.

## Limits

Static SQL cannot reveal table size, row count, workload, current lock holders, storage speed, replication lag, duration, or application semantics. A finding describes possible operational impact, not certain downtime; absence of a finding is not a universal safety guarantee. M8 does not cover every PostgreSQL version or ORM, malicious SQL, business-data correctness, zero-downtime guarantees, production SLAs, backup correctness, WAL archiving, or PITR. Backup/WAL/PITR remains M9.
