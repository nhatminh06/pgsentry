#!/usr/bin/env python3
import argparse, json
from pathlib import Path

p=argparse.ArgumentParser(); p.add_argument("events",type=Path); p.add_argument("--failure-ns",type=int,required=True); p.add_argument("--present",default=""); a=p.parse_args()
events=[json.loads(x) for x in a.events.read_text().splitlines() if x.strip()]
writes=[x for x in events if x.get("kind")=="write"]
before=[x for x in writes if x.get("outcome")=="confirmed_success" and x["attempt_completed_ns"] < a.failure_ns]
after=[x for x in writes if x.get("outcome")=="confirmed_success" and x["attempt_completed_ns"] >= a.failure_ns]
post=[x for x in writes if x["attempt_completed_ns"] >= a.failure_ns]
failed=[x for x in post if x.get("outcome") not in ("confirmed_success","duplicate_key_confirmed_committed")]
acked={x["seq"] for x in writes if x.get("outcome") in ("confirmed_success","duplicate_key_confirmed_committed")}
present={int(x) for x in a.present.split(",") if x}
if failed:
    first_failure=failed[0]["attempt_started_ns"]
    last_failure=failed[-1]["attempt_completed_ns"]
    prior=[x for x in writes if x.get("outcome")=="confirmed_success" and x["attempt_completed_ns"] < first_failure]
    resumed=[x for x in writes if x.get("outcome")=="confirmed_success" and x["attempt_completed_ns"] > last_failure]
    last=prior[-1]["attempt_completed_ns"] if prior else a.failure_ns
    first=resumed[0]["attempt_completed_ns"] if resumed else None
else:
    last=before[-1]["attempt_completed_ns"] if before else a.failure_ns
    first=after[0]["attempt_completed_ns"] if after else None
result={"last_success_before_failure_ns":last,"first_success_after_failure_ns":first,"observed_write_interruption_ms":round((first-last)/1e6,3) if first else None,"acknowledged_before_failure":len(before),"highest_acknowledged_sequence":max(acked,default=0),"retained_acknowledged_sequences":len(acked & present),"acknowledged_rows_missing":len(acked-present),"ambiguous_transactions":sum(x.get("outcome")=="ambiguous" for x in writes),"duplicate_key_retries":sum(x.get("outcome")=="duplicate_key_confirmed_committed" for x in writes),"confirmed_failures":sum(x.get("outcome")=="confirmed_failure" for x in writes)}
print(json.dumps(result,sort_keys=True))
