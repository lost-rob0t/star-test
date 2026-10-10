"""Exercise the actual JSON data boundary. No Prolog goals come from input."""
import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def run(value):
    return subprocess.run(
        ["swipl", "-q", "-f", "none", "--no-packs", "-s", "oracle/cli.pl"],
        cwd=ROOT, input=json.dumps(value), text=True, capture_output=True, timeout=10)

class CliTests(unittest.TestCase):
    def test_good(self):
        result = run(json.loads((ROOT / "traces/ack-restart.json").read_text()))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["verdict"], "pass")

    def test_mutant(self):
        result = run(json.loads((ROOT / "traces/ack-before-commit.json").read_text()))
        self.assertEqual(result.returncode, 1, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["verdict"], "fail")
        self.assertEqual(report["first_failure"], 3)

    def test_bad_envelopes(self):
        for value in ({}, {"events": [], "complete": True, "extra": 1},
                      {"events": [{"op": "halt"}], "complete": True},
                      {"events": [{"op": "begin", "extra": 1}], "complete": True},
                      {"events": [], "complete": "yes"}):
            with self.subTest(value=value):
                result = run(value)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(json.loads(result.stdout)["verdict"], "error")

    def test_json_string_booleans_rejected(self):
        pristine = json.loads((ROOT / "traces/ack-restart.json").read_text())
        for field in ("complete", "receipt", "active"):
            for literal in ("true", "false"):
                value = json.loads(json.dumps(pristine))
                target = value if field == "complete" else value["events"][-1]
                target[field] = literal
                with self.subTest(field=field, literal=literal):
                    result = run(value)
                    self.assertEqual(result.returncode, 2, result.stdout)
                    self.assertEqual(json.loads(result.stdout)["verdict"], "error")

    def test_oversized_input(self):
        result = run({"events": [], "complete": True, "padding": "x" * 65537})
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["verdict"], "error")

    def test_trailing_json_rejected(self):
        result = subprocess.run(
            ["swipl", "-q", "-f", "none", "--no-packs", "-s", "oracle/cli.pl"],
            cwd=ROOT, input='{"events": [], "complete": true} {}', text=True,
            capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 2, result.stdout)

    def test_incomplete(self):
        result = run({"events": [{"op": "begin"}], "complete": False})
        self.assertEqual(result.returncode, 3)
        self.assertEqual(json.loads(result.stdout)["verdict"], "inconclusive")

if __name__ == "__main__":
    unittest.main()
