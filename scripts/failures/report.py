#!/usr/bin/env python3
import json, statistics, sys
from pathlib import Path

root=Path(sys.argv[1]); rows=[json.loads(p.read_text()) for p in sorted(root.glob("*/result.json"))]
rows=[r for r in rows if r.get("trial", 0) > 0]
lines=["# M5 failure matrix", "", "| Scenario | Trial | Old primary | New primary | Interruption ms | Acked missing | Ambiguous | Final |", "| --- | ---: | --- | --- | ---: | ---: | ---: | --- |"]
for r in rows:
    lines.append(f"| {r['scenario']} | {r['trial']} | {r['old_primary']} | {r['new_primary']} | {r['observed_write_interruption_ms']} | {r['acknowledged_rows_missing']} | {r['ambiguous_transactions']} | {r['result']} |")
lines += ["", "## Repeated-scenario laboratory observations", ""]
for name in ("primary-service-loss","primary-vm-loss"):
    values=[r["observed_write_interruption_ms"] for r in rows if r["scenario"]==name and r["observed_write_interruption_ms"] is not None]
    if values: lines.append(f"- {name}: min={min(values):.3f} ms, median={statistics.median(values):.3f} ms, max={max(values):.3f} ms ({len(values)} trials)")
report="\n".join(lines)+"\n"; (root/"report.md").write_text(report); print(report,end="")
