#!/usr/bin/env python3
import json, statistics, sys
from pathlib import Path

root=Path(sys.argv[1]); rows=[json.loads(p.read_text()) for p in sorted(root.glob("*/result.json"))]
latency=[r for r in rows if r.get("scenario")=="healthy-latency"]
failures=[r for r in rows if r.get("scenario")!="healthy-latency"]
lines=["# M6 synchronous durability experiments","","## Healthy commit latency","","| Policy | Samples | Median ms | p95 ms | Max ms |","| --- | ---: | ---: | ---: | ---: |"]
for r in latency: lines.append(f"| {r['policy']} | {r['samples']} | {r['median_ms']:.3f} | {r['p95_ms']:.3f} | {r['max_ms']:.3f} |")
lines += ["","## Failure comparison","","| Policy | Scenario | Trial | Old primary | New primary | Interruption ms | Acked missing | Ambiguous | Result |","| --- | --- | ---: | --- | --- | ---: | ---: | ---: | --- |"]
for r in failures: lines.append(f"| {r['policy']} | {r['scenario']} | {r['trial']} | {r['old_primary']} | {r['new_primary']} | {r['observed_write_interruption_ms']} | {r['acknowledged_rows_missing']} | {r['ambiguous_transactions']} | {r['result']} |")
lines += ["","## Repeated primary-loss observations",""]
for mode in ("async","sync"):
    selected=[r for r in failures if r["policy"]==mode and r["scenario"]=="primary-vm-loss"]
    values=[r["observed_write_interruption_ms"] for r in selected if r["observed_write_interruption_ms"] is not None]
    if values: lines.append(f"- {mode}: min={min(values):.3f} ms, median={statistics.median(values):.3f} ms, max={max(values):.3f} ms; missing acknowledged={sum(r['acknowledged_rows_missing'] for r in selected)}; ambiguous={sum(r['ambiguous_transactions'] for r in selected)}")
report="\n".join(lines)+"\n"; (root/"report.md").write_text(report); print(report,end="")
