package pgsafe

var rules = []Rule{
	{"PGSAFE001", "CREATE INDEX without CONCURRENTLY", High, "A regular index build can block writes on a live table.", "Consider CREATE INDEX CONCURRENTLY; it runs longer and a failed build can leave an invalid index.", "operational risk"},
	{"PGSAFE002", "DROP INDEX without CONCURRENTLY", High, "A regular index drop takes an ACCESS EXCLUSIVE lock on the table.", "Use DROP INDEX CONCURRENTLY when PostgreSQL permits it; run it outside a transaction block.", "operational risk"},
	{"PGSAFE003", "Concurrent index operation in transaction", High, "PostgreSQL rejects CREATE/DROP INDEX CONCURRENTLY inside a transaction block.", "Disable migration-runner transaction wrapping for this migration.", "definite"},
	{"PGSAFE004", "ALTER COLUMN TYPE", High, "The command takes strong locks and may rewrite the table or rebuild indexes; binary-compatible conversions can avoid a rewrite.", "For large live tables, consider expand/backfill/contract and bound lock acquisition.", "operational risk"},
	{"PGSAFE005", "SET NOT NULL validation", High, "PostgreSQL may scan existing rows while holding a strong table lock unless it can use a proven valid constraint.", "Stage a CHECK (column IS NOT NULL) NOT VALID, validate it, then set NOT NULL.", "operational risk"},
	{"PGSAFE006", "Immediate CHECK constraint validation", High, "Adding a validated CHECK scans existing rows and takes non-zero locks.", "Add the CHECK NOT VALID, then VALIDATE CONSTRAINT in a controlled step.", "operational risk"},
	{"PGSAFE007", "VALIDATE CONSTRAINT", Warning, "Validation scans existing rows and takes a SHARE UPDATE EXCLUSIVE lock, though normal writes can continue.", "Run validation as a separately monitored step with suitable statement-timeout policy.", "operational risk"},
	{"PGSAFE008", "Immediate foreign-key validation", High, "Validation scans data and acquires locks involving both referencing and referenced relations.", "Add the foreign key NOT VALID, then validate it in a controlled later step.", "operational risk"},
	{"PGSAFE009", "Destructive DROP", Critical, "Dropping a database, schema, or live table destroys schema/data and may take strong locks.", "Use an explicitly reviewed deprecation and backup/recovery plan before a later drop.", "definite destructive action"},
	{"PGSAFE010", "TRUNCATE", Critical, "TRUNCATE removes all rows immediately and requires ACCESS EXCLUSIVE locks.", "Use a reviewed, bounded data-retention operation when wholesale removal is not intended.", "definite destructive action"},
	{"PGSAFE011", "DELETE without WHERE", Critical, "The statement can delete every row and generate substantial WAL and row locks.", "Add an intentional predicate and batch large deletions; review row counts first.", "definite statement scope"},
	{"PGSAFE012", "UPDATE without WHERE", High, "The statement updates every row, generating WAL, row locks, and table bloat.", "Add an intentional predicate and batch large updates.", "definite statement scope"},
	{"PGSAFE013", "DROP COLUMN", Critical, "Dropping a column is destructive and ALTER TABLE requires strong locking.", "Remove application dependencies first and defer the drop to a reviewed cleanup migration.", "definite destructive action"},
	{"PGSAFE014", "Rewrite or strong-lock maintenance", High, "This maintenance form can block access or rewrite substantial storage.", "Use an available concurrent form or a bounded maintenance window.", "operational risk"},
	{"PGSAFE015", "Unbounded lock acquisition", Warning, "This lock-heavy statement has no preceding non-zero lock_timeout in the migration.", "Set a non-zero lock_timeout; it bounds lock waiting, not total statement runtime.", "operational risk"},
	{"PGSAFE016", "Volatile ADD COLUMN default", High, "PostgreSQL 16 fast defaults avoid a rewrite only for non-volatile expressions; a volatile default can evaluate for every row.", "Add the column without the volatile default, backfill in batches, then establish the desired default.", "operational risk"},
}

func Rules() []Rule { out := make([]Rule, len(rules)); copy(out, rules); return out }
func RuleByID(id string) (Rule, bool) {
	for _, r := range rules {
		if r.ID == id {
			return r, true
		}
	}
	return Rule{}, false
}
