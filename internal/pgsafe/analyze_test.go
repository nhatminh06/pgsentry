package pgsafe

import (
	"bytes"
	"encoding/json"
	"os"
	"reflect"
	"testing"
)

func ids(ds []Diagnostic) map[string]bool {
	m := map[string]bool{}
	for _, d := range ds {
		m[d.RuleID] = true
	}
	return m
}
func TestRequiredRules(t *testing.T) {
	b, err := os.ReadFile("../../testdata/migrations/unsafe/risky.sql")
	if err != nil {
		t.Fatal(err)
	}
	ds, n, err := Analyze("risky.sql", string(b), Options{High, "single"})
	if err != nil {
		t.Fatal(err)
	}
	if n != 17 {
		t.Fatalf("statements=%d", n)
	}
	got := ids(ds)
	for _, id := range []string{"PGSAFE001", "PGSAFE002", "PGSAFE003", "PGSAFE004", "PGSAFE005", "PGSAFE006", "PGSAFE008", "PGSAFE009", "PGSAFE010", "PGSAFE011", "PGSAFE012", "PGSAFE013", "PGSAFE014", "PGSAFE015", "PGSAFE016"} {
		if !got[id] {
			t.Errorf("missing %s", id)
		}
	}
}
func TestModernDefaultAndStagedPatterns(t *testing.T) {
	b, _ := os.ReadFile("../../testdata/migrations/safe/staged.sql")
	ds, _, err := Analyze("safe.sql", string(b), Options{High, "single"})
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range ds {
		if d.Severity.Rank() >= High.Rank() {
			t.Errorf("unexpected high finding: %s", d.RuleID)
		}
	}
	if !ids(ds)["PGSAFE007"] {
		t.Error("VALIDATE should retain a warning")
	}
}
func TestParserEdges(t *testing.T) {
	b, _ := os.ReadFile("../../testdata/migrations/edge/quoted.sql")
	_, n, err := Analyze("quoted.sql", string(b), Options{High, "single"})
	if err != nil {
		t.Fatal(err)
	}
	if n != 3 {
		t.Fatalf("statements=%d", n)
	}
}
func TestWrappedTransaction(t *testing.T) {
	ds, _, err := Analyze("x.sql", "CREATE INDEX CONCURRENTLY i ON t(a);", Options{High, "wrapped"})
	if err != nil {
		t.Fatal(err)
	}
	if !ids(ds)["PGSAFE003"] {
		t.Fatal("missing transaction incompatibility")
	}
}
func TestSuppression(t *testing.T) {
	b, _ := os.ReadFile("../../testdata/migrations/edge/suppressed.sql")
	ds, _, err := Analyze("s.sql", string(b), Options{High, "single"})
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, d := range ds {
		if d.RuleID == "PGSAFE001" {
			found = d.Suppressed && d.SuppressionReason != ""
		}
	}
	if !found {
		t.Fatal("suppression not audited")
	}
	_, _, err = Analyze("bad.sql", "-- pgsafe: ignore PGSAFE001\nCREATE INDEX i ON t(a);", Options{High, "single"})
	if err == nil {
		t.Fatal("malformed suppression accepted")
	}
}
func TestMalformedSQL(t *testing.T) {
	_, _, err := Analyze("bad.sql", "ALTER TABLE t ADD CONSTRAINT x CHECK (", Options{High, "single"})
	if err == nil {
		t.Fatal("invalid SQL accepted")
	}
}
func TestDeterministicJSON(t *testing.T) {
	opts := Options{High, "single"}
	a, err := Check([]string{"../../testdata/migrations/unsafe/risky.sql"}, bytes.NewReader(nil), opts)
	if err != nil {
		t.Fatal(err)
	}
	b, err := Check([]string{"../../testdata/migrations/unsafe/risky.sql"}, bytes.NewReader(nil), opts)
	if err != nil {
		t.Fatal(err)
	}
	ja, _ := json.Marshal(a)
	jb, _ := json.Marshal(b)
	if !reflect.DeepEqual(ja, jb) {
		t.Fatal("output is not deterministic")
	}
	if a.ExitCode != 1 {
		t.Fatalf("exit=%d", a.ExitCode)
	}
}
