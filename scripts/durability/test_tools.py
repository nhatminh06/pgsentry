#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE=Path(__file__).parent
spec=importlib.util.spec_from_file_location("latency",HERE/"latency.py"); latency=importlib.util.module_from_spec(spec); spec.loader.exec_module(latency)

class DurabilityToolsTest(unittest.TestCase):
    def test_latency_nearest_rank(self):
        events=[{"kind":"write","outcome":"confirmed_success","latency_ms":value} for value in range(1,101)]
        events.append({"kind":"write","outcome":"confirmed_failure","latency_ms":999})
        self.assertEqual(latency.summarize(events),{"samples":100,"median_ms":50.5,"p95_ms":95,"max_ms":100})

    def test_report_parses_policy_results(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            latency_dir=root/"latency"; latency_dir.mkdir()
            (latency_dir/"result.json").write_text(json.dumps({"policy":"async","scenario":"healthy-latency","samples":40,"median_ms":1.0,"p95_ms":2.0,"max_ms":3.0,"result":"passed"}))
            failure_dir=root/"failure"; failure_dir.mkdir()
            (failure_dir/"result.json").write_text(json.dumps({"policy":"async","scenario":"primary-vm-loss","trial":1,"old_primary":"pg-01","new_primary":"pg-02","observed_write_interruption_ms":10.0,"acknowledged_rows_missing":0,"ambiguous_transactions":1,"result":"passed"}))
            subprocess.run([str(HERE/"report.py"),str(root)],check=True,capture_output=True,text=True)
            report=(root/"report.md").read_text()
            self.assertIn("| async | 40 | 1.000 | 2.000 | 3.000 |",report)
            self.assertIn("| async | primary-vm-loss | 1 |",report)

if __name__ == "__main__": unittest.main()
