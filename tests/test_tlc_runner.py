"""Negative controls for the TLC result classifier; no Java/download needed."""

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("startest_check_tlc", ROOT / "scripts" / "check-tlc.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)

MUTANT_TRACE = '''Error: Invariant AckDurable is violated.
Error: The behavior up to this point is:
State 1: <Initial predicate>
/\\ lastAction = "Init"
/\\ ackReceived = FALSE
/\\ db = [status |-> "absent", canonical |-> {}]
State 5: <AckBeforeCommit line 200, col 1>
/\\ lastAction = "AckBeforeCommit"
/\\ ackReceived = TRUE
/\\ db = [status |-> "open", canonical |-> {}, staged |-> {a}]
'''


class TlcClassificationTests(unittest.TestCase):
    def test_normal_completed_success(self):
        self.assertEqual(
            RUNNER.classify("normal", 0, RUNNER.SUCCESS),
            (True, "finite-model-safety-pass"),
        )

    def test_normal_nonzero_never_passes(self):
        self.assertFalse(RUNNER.classify("normal", 1, RUNNER.SUCCESS)[0])

    def test_normal_zero_without_completion_never_passes(self):
        self.assertFalse(RUNNER.classify("normal", 0, "Starting model checking...")[0])

    def test_normal_violation_overrides_success_text(self):
        self.assertFalse(RUNNER.classify("normal", 0, RUNNER.SUCCESS + MUTANT_TRACE)[0])

    def test_exact_named_mutant_trace(self):
        self.assertEqual(
            RUNNER.classify("mutant", 12, MUTANT_TRACE),
            (True, "expected-mutant-counterexample"),
        )

    def test_other_invariant_never_passes(self):
        text = MUTANT_TRACE.replace("Invariant AckDurable", "Invariant AtomicPromotion")
        self.assertFalse(RUNNER.classify("mutant", 12, text)[0])

    def test_parser_error_never_passes(self):
        self.assertFalse(RUNNER.classify("mutant", 150, "Parsing or semantic analysis failed.")[0])

    def test_generic_nonzero_is_not_a_counterexample(self):
        self.assertFalse(RUNNER.classify("mutant", 1, MUTANT_TRACE)[0])

    def test_missing_expected_action_never_passes(self):
        text = MUTANT_TRACE.replace('lastAction = "AckBeforeCommit"', 'lastAction = "Promote"')
        self.assertFalse(RUNNER.classify("mutant", 12, text)[0])

    def test_expected_action_in_earlier_state_is_insufficient(self):
        text = MUTANT_TRACE + '''State 6: <ReadCanonical>
/\\ lastAction = "ReadCanonical"
/\\ ackReceived = TRUE
/\\ db = [status |-> "open", canonical |-> {}]
'''
        self.assertFalse(RUNNER.classify("mutant", 12, text)[0])

    def test_missing_received_success_never_passes(self):
        text = MUTANT_TRACE.replace("ackReceived = TRUE", "ackReceived = FALSE")
        self.assertFalse(RUNNER.classify("mutant", 12, text)[0])

    def test_missing_open_state_never_passes(self):
        text = MUTANT_TRACE.replace('status |-> "open"', 'status |-> "committed"')
        self.assertFalse(RUNNER.classify("mutant", 12, text)[0])

    def test_missing_empty_canonical_state_never_passes(self):
        text = MUTANT_TRACE.replace("canonical |-> {}", "canonical |-> {a}")
        self.assertFalse(RUNNER.classify("mutant", 12, text)[0])

    def test_timeout_code_never_passes(self):
        self.assertFalse(RUNNER.classify("mutant", None, MUTANT_TRACE)[0])
        self.assertFalse(RUNNER.classify("normal", None, RUNNER.SUCCESS)[0])

    def test_multiple_violations_never_pass(self):
        text = MUTANT_TRACE + "Invariant StageLifecycle is violated.\n"
        self.assertFalse(RUNNER.classify("mutant", 12, text)[0])


if __name__ == "__main__":
    unittest.main()
