package pgsafe

import "strings"

const SchemaVersion = "1"

type Severity string

const (
	Info     Severity = "INFO"
	Warning  Severity = "WARNING"
	High     Severity = "HIGH"
	Critical Severity = "CRITICAL"
)

func (s Severity) Rank() int { return map[Severity]int{Info: 0, Warning: 1, High: 2, Critical: 3}[s] }
func ParseSeverity(s string) (Severity, bool) {
	switch strings.ToUpper(s) {
	case "INFO":
		return Info, true
	case "WARNING":
		return Warning, true
	case "HIGH":
		return High, true
	case "CRITICAL":
		return Critical, true
	}
	return "", false
}

type Rule struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Severity    Severity `json:"severity"`
	Risk        string   `json:"risk"`
	Alternative string   `json:"alternative"`
	Confidence  string   `json:"confidence"`
}
type Diagnostic struct {
	RuleID            string   `json:"rule_id"`
	Severity          Severity `json:"severity"`
	File              string   `json:"file"`
	Statement         int      `json:"statement"`
	Line              int      `json:"line"`
	Column            int      `json:"column"`
	StatementType     string   `json:"statement_type"`
	Title             string   `json:"title"`
	Explanation       string   `json:"explanation"`
	Risk              string   `json:"operational_risk"`
	Alternative       string   `json:"safer_alternative"`
	Confidence        string   `json:"confidence"`
	SQL               string   `json:"sql"`
	Suppressed        bool     `json:"suppressed"`
	SuppressionReason string   `json:"suppression_reason,omitempty"`
}
type Summary struct {
	Files       int      `json:"files"`
	Statements  int      `json:"statements"`
	Diagnostics int      `json:"diagnostics"`
	Suppressed  int      `json:"suppressed"`
	Failing     int      `json:"failing"`
	FailOn      Severity `json:"fail_on"`
}
type Report struct {
	SchemaVersion     string       `json:"schema_version"`
	PostgreSQLVersion int          `json:"postgresql_version"`
	Diagnostics       []Diagnostic `json:"diagnostics"`
	Summary           Summary      `json:"summary"`
	ExitCode          int          `json:"exit_code"`
}
type Options struct {
	FailOn          Severity
	TransactionMode string
}
