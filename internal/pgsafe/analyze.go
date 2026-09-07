package pgsafe

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"

	pgquery "github.com/pganalyze/pg_query_go/v5"
)

type rawTree struct {
	Version int       `json:"version"`
	Stmts   []rawStmt `json:"stmts"`
}
type rawStmt struct {
	Stmt     map[string]any `json:"stmt"`
	Location int            `json:"stmt_location"`
	Length   int            `json:"stmt_len"`
}

var suppressionLine = regexp.MustCompile(`^\s*--\s*pgsafe:\s*ignore\s+(PGSAFE[0-9]{3})\s+reason="([^"]+)"\s*$`)

func Analyze(file, sql string, opts Options) ([]Diagnostic, int, error) {
	if opts.TransactionMode != "single" && opts.TransactionMode != "wrapped" {
		return nil, 0, fmt.Errorf("transaction mode must be single or wrapped")
	}
	j, err := pgquery.ParseToJSON(sql)
	if err != nil {
		return nil, 0, err
	}
	var tree rawTree
	if err = json.Unmarshal([]byte(j), &tree); err != nil {
		return nil, 0, err
	}
	suppress, err := suppressions(sql, tree.Stmts)
	if err != nil {
		return nil, 0, err
	}
	lockBounded := false
	explicitTxn := false
	out := []Diagnostic{}
	for i, s := range tree.Stmts {
		typ, node := root(s.Stmt)
		text := statementSQL(sql, s)
		line, col := lineCol(sql, statementStart(sql, s))
		ids := []string{}
		lockHeavy := false
		switch typ {
		case "TransactionStmt":
			kind := str(node, "kind")
			if kind == "TRANS_STMT_BEGIN" || kind == "TRANS_STMT_START" {
				explicitTxn = true
			}
			if kind == "TRANS_STMT_COMMIT" || kind == "TRANS_STMT_ROLLBACK" {
				explicitTxn = false
			}
		case "VariableSetStmt":
			if str(node, "name") == "lock_timeout" {
				lockBounded = !strings.Contains(strings.ToLower(text), "= 0") && !strings.Contains(strings.ToLower(text), "= '0'")
			}
		case "IndexStmt":
			concurrent := boolean(node, "concurrent")
			if !concurrent {
				ids = append(ids, "PGSAFE001")
				lockHeavy = true
			}
			if concurrent && (explicitTxn || opts.TransactionMode == "wrapped") {
				ids = append(ids, "PGSAFE003")
			}
		case "DropStmt":
			obj := str(node, "removeType")
			concurrent := boolean(node, "concurrent")
			if obj == "OBJECT_INDEX" && !concurrent {
				ids = append(ids, "PGSAFE002")
				lockHeavy = true
			}
			if obj == "OBJECT_INDEX" && concurrent && (explicitTxn || opts.TransactionMode == "wrapped") {
				ids = append(ids, "PGSAFE003")
			}
			if obj == "OBJECT_TABLE" || obj == "OBJECT_SCHEMA" || obj == "OBJECT_DATABASE" {
				ids = append(ids, "PGSAFE009")
				lockHeavy = true
			}
		case "TruncateStmt":
			ids = append(ids, "PGSAFE010")
			lockHeavy = true
		case "DeleteStmt":
			if node["whereClause"] == nil {
				ids = append(ids, "PGSAFE011")
			}
		case "UpdateStmt":
			if node["whereClause"] == nil {
				ids = append(ids, "PGSAFE012")
			}
		case "AlterTableStmt":
			for _, cmd := range objects(node["cmds"], "AlterTableCmd") {
				switch str(cmd, "subtype") {
				case "AT_AlterColumnType":
					ids = append(ids, "PGSAFE004")
					lockHeavy = true
				case "AT_SetNotNull":
					ids = append(ids, "PGSAFE005")
					lockHeavy = true
				case "AT_DropColumn":
					ids = append(ids, "PGSAFE013")
					lockHeavy = true
				case "AT_ValidateConstraint":
					ids = append(ids, "PGSAFE007")
					lockHeavy = true
				case "AT_AddConstraint":
					c := child(cmd, "def", "Constraint")
					if boolean(c, "initially_valid") {
						if str(c, "contype") == "CONSTR_CHECK" {
							ids = append(ids, "PGSAFE006")
							lockHeavy = true
						}
						if str(c, "contype") == "CONSTR_FOREIGN" {
							ids = append(ids, "PGSAFE008")
							lockHeavy = true
						}
					}
				case "AT_AddColumn":
					if volatileDefault(child(cmd, "def", "ColumnDef")) {
						ids = append(ids, "PGSAFE016")
						lockHeavy = true
					}
				}
			}
		case "ClusterStmt":
			ids = append(ids, "PGSAFE014")
			lockHeavy = true
		case "VacuumStmt":
			if hasOption(node, "full") {
				ids = append(ids, "PGSAFE014")
				lockHeavy = true
			}
		case "ReindexStmt":
			if !boolean(node, "concurrent") {
				ids = append(ids, "PGSAFE014")
				lockHeavy = true
			}
		}
		if lockHeavy && !lockBounded {
			ids = append(ids, "PGSAFE015")
		}
		sort.Strings(ids)
		for _, id := range unique(ids) {
			r, _ := RuleByID(id)
			d := Diagnostic{r.ID, r.Severity, file, i + 1, line, col, typ, r.Name, r.Risk, r.Risk, r.Alternative, r.Confidence, text, false, ""}
			if reason, ok := suppress[i+1][id]; ok {
				d.Suppressed = true
				d.SuppressionReason = reason
			}
			out = append(out, d)
		}
	}
	return out, len(tree.Stmts), nil
}

func root(m map[string]any) (string, map[string]any) {
	for k, v := range m {
		if n, ok := v.(map[string]any); ok {
			return k, n
		}
	}
	return "Unknown", map[string]any{}
}
func str(m map[string]any, k string) string   { v, _ := m[k].(string); return v }
func boolean(m map[string]any, k string) bool { v, _ := m[k].(bool); return v }
func child(m map[string]any, keys ...string) map[string]any {
	cur := m
	for _, k := range keys {
		n, _ := cur[k].(map[string]any)
		cur = n
	}
	return cur
}
func objects(v any, key string) []map[string]any {
	a, _ := v.([]any)
	out := []map[string]any{}
	for _, x := range a {
		m, _ := x.(map[string]any)
		if n, ok := m[key].(map[string]any); ok {
			out = append(out, n)
		}
	}
	return out
}
func hasOption(m map[string]any, name string) bool {
	for _, x := range objects(m["options"], "DefElem") {
		if str(x, "defname") == name {
			return true
		}
	}
	return false
}
func volatileDefault(col map[string]any) bool {
	volatile := map[string]bool{"random": true, "clock_timestamp": true, "timeofday": true, "nextval": true, "gen_random_uuid": true}
	for _, c := range objects(col["constraints"], "Constraint") {
		if str(c, "contype") != "CONSTR_DEFAULT" {
			continue
		}
		b, _ := json.Marshal(c["raw_expr"])
		var walk func(any) bool
		walk = func(v any) bool {
			switch x := v.(type) {
			case map[string]any:
				if f, ok := x["FuncCall"].(map[string]any); ok {
					for _, s := range objects(f["funcname"], "String") {
						if volatile[str(s, "sval")] {
							return true
						}
					}
				}
				for _, z := range x {
					if walk(z) {
						return true
					}
				}
			case []any:
				for _, z := range x {
					if walk(z) {
						return true
					}
				}
			}
			return false
		}
		var raw any
		_ = json.Unmarshal(b, &raw)
		if walk(raw) {
			return true
		}
	}
	return false
}
func statementSQL(sql string, s rawStmt) string {
	start := statementStart(sql, s)
	if start < 0 {
		start = 0
	}
	end := len(sql)
	if s.Length > 0 && s.Location+s.Length <= len(sql) {
		end = s.Location + s.Length
	}
	return strings.TrimSpace(sql[start:end])
}

func statementStart(sql string, s rawStmt) int {
	i := s.Location
	if i < 0 {
		i = 0
	}
	for i < len(sql) {
		if strings.ContainsRune(" \t\r\n", rune(sql[i])) {
			i++
			continue
		}
		if strings.HasPrefix(sql[i:], "--") {
			if n := strings.IndexByte(sql[i:], '\n'); n >= 0 {
				i += n + 1
				continue
			}
			return len(sql)
		}
		if strings.HasPrefix(sql[i:], "/*") {
			if n := strings.Index(sql[i+2:], "*/"); n >= 0 {
				i += n + 4
				continue
			}
		}
		break
	}
	return i
}
func lineCol(s string, offset int) (int, int) {
	if offset < 0 {
		offset = 0
	}
	line, col := 1, 1
	for i := 0; i < offset && i < len(s); i++ {
		if s[i] == '\n' {
			line++
			col = 1
		} else {
			col++
		}
	}
	return line, col
}
func unique(in []string) []string {
	out := []string{}
	last := ""
	for _, x := range in {
		if x != last {
			out = append(out, x)
			last = x
		}
	}
	return out
}
func suppressions(sql string, stmts []rawStmt) (map[int]map[string]string, error) {
	out := map[int]map[string]string{}
	lines := strings.Split(sql, "\n")
	offset := 0
	for _, line := range lines {
		if strings.Contains(line, "pgsafe:") {
			m := suppressionLine.FindStringSubmatch(line)
			if m == nil {
				return nil, fmt.Errorf("malformed pgsafe suppression at line %d", strings.Count(sql[:offset], "\n")+1)
			}
			if _, ok := RuleByID(m[1]); !ok {
				return nil, fmt.Errorf("unknown suppression rule %s", m[1])
			}
			stmt := 0
			for i, s := range stmts {
				if statementStart(sql, s) > offset {
					stmt = i + 1
					break
				}
			}
			if stmt == 0 && len(stmts) == 1 {
				stmt = 1 // PostgreSQL reports the first statement location as zero, including leading comments.
			}
			if stmt == 0 {
				return nil, fmt.Errorf("suppression has no following statement")
			}
			if out[stmt] == nil {
				out[stmt] = map[string]string{}
			}
			out[stmt][m[1]] = m[2]
		}
		offset += len(line) + 1
	}
	return out, nil
}
