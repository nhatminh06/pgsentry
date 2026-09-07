#!/usr/bin/env python3
import json, sys
from pathlib import Path
root=Path(sys.argv[1]); rows=[json.loads(p.read_text()) for p in sorted(root.glob("*/result.json"))]
lines=["# M7 network-partition and DCS-chaos matrix","","| Scenario | Trial | Old primary | New primary | Interruption ms | Max writable | Acked missing | Ambiguous | Result |","| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | --- |"]
for r in rows: lines.append(f"| {r['scenario']} | {r['trial']} | {r['old_primary']} | {r['new_primary']} | {r['observed_write_interruption_ms']} | {r['maximum_writable_primaries_observed']} | {r['acknowledged_rows_missing']} | {r['ambiguous_transactions']} | {r['result']} |")
report="\n".join(lines)+"\n"; (root/"report.md").write_text(report); print(report,end="")
