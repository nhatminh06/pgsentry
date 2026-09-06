#!/usr/bin/env python3
import json, math, statistics, sys
from pathlib import Path

def summarize(events):
    values=[x["latency_ms"] for x in events if x.get("kind")=="write" and x.get("outcome")=="confirmed_success"]
    if not values: raise ValueError("no successful latency samples")
    ordered=sorted(values); p95=ordered[max(0, math.ceil(len(ordered)*.95)-1)]
    return {"samples":len(values),"median_ms":round(statistics.median(values),3),"p95_ms":round(p95,3),"max_ms":round(max(values),3)}

if __name__ == "__main__":
    events=[json.loads(x) for x in Path(sys.argv[1]).read_text().splitlines() if x.strip()]
    try: result=summarize(events)
    except ValueError as error: raise SystemExit(str(error)) from error
    print(json.dumps(result,sort_keys=True))
