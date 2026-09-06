#!/usr/bin/env python3
"""Bounded M5 write workload using only the stable HAProxy endpoint."""
import argparse
import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


def emit(handle, **event):
    event["wall_time"] = datetime.now(timezone.utc).isoformat()
    event["monotonic_ns"] = time.monotonic_ns()
    handle.write(json.dumps(event, sort_keys=True) + "\n")
    handle.flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--events", type=Path, required=True)
    parser.add_argument("--stop-file", type=Path, required=True)
    parser.add_argument("--max-seconds", type=int, default=240)
    parser.add_argument("--interval-ms", type=int, default=250)
    parser.add_argument("--policy", default="async")
    parser.add_argument("--statement-timeout-ms", type=int, default=4000)
    args = parser.parse_args()
    password = os.environ["PGPASSWORD"]
    env = {**os.environ, "PGPASSWORD": password, "PGCONNECT_TIMEOUT": "2"}
    args.events.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + args.max_seconds
    seq = 1
    with args.events.open("a", encoding="utf-8") as events:
        emit(events, kind="workload_start", run_id=args.run_id, policy=args.policy)
        while not args.stop_file.exists() and time.monotonic() < deadline:
            sql = (
                f"SET statement_timeout='{args.statement_timeout_ms}ms'; "
                "INSERT INTO public.m5_probe(run_id,seq,client_sent_at) "
                f"VALUES ('{args.run_id}',{seq},clock_timestamp());"
            )
            started = time.monotonic_ns()
            try:
                proc = subprocess.run(
                    ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", args.host,
                     "-p", str(args.port), "-U", "postgres", "-d", "postgres",
                     "-Atqc", sql], env=env, text=True, capture_output=True,
                    timeout=max(2, args.statement_timeout_ms / 1000 + 2), check=False,
                )
                message = (proc.stderr or proc.stdout).strip()[-500:]
                if proc.returncode == 0:
                    outcome = "confirmed_success"
                elif "duplicate key" in message.lower():
                    outcome = "duplicate_key_confirmed_committed"
                elif any(x in message.lower() for x in
                         ("server closed the connection", "connection to server was lost",
                          "unexpectedly")):
                    outcome = "ambiguous"
                else:
                    outcome = "confirmed_failure"
            except subprocess.TimeoutExpired:
                message = "client timeout after statement submission"
                outcome = "ambiguous"
            completed = time.monotonic_ns()
            emit(events, kind="write", run_id=args.run_id, seq=seq,
                 attempt_started_ns=started, attempt_completed_ns=completed,
                 latency_ms=round((completed - started) / 1e6, 3),
                 policy=args.policy, outcome=outcome, error=message)
            # Retry an ambiguous sequence with the same id. A duplicate-key
            # response proves the earlier attempt committed before its reply
            # was lost; a successful retry proves it had not committed.
            if outcome != "ambiguous":
                seq += 1
            time.sleep(args.interval_ms / 1000)
        emit(events, kind="workload_stop", run_id=args.run_id)


if __name__ == "__main__":
    main()
