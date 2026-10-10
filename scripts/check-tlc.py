#!/usr/bin/env python3
"""Run the bounded model and require the intended named mutant failure."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "model" / "StagedImport.tla"
LOCK = ROOT / "model" / "tla2tools.lock.json"
TIMEOUT_SECONDS = 180
SUCCESS = "Model checking completed. No error has been found."
TRACE_HEADER = "The behavior up to this point is:"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def classify(kind, returncode, text):
    """A parser crash, deadlock, timeout, or different violation never passes."""
    names = re.findall(r"Invariant ([A-Za-z_][A-Za-z_0-9]*) is violated\.", text)
    if kind == "normal":
        passed = returncode == 0 and SUCCESS in text and not names
        return passed, "finite-model-safety-pass" if passed else "check-failed"
    states = re.split(r"(?m)^State [0-9]+:", text)
    last_state = states[-1] if len(states) > 1 else ""
    expected = (
        returncode == 12  # Official v1.7.4 EC.ExitStatus.VIOLATION_SAFETY.
        and names == ["AckDurable"]
        and TRACE_HEADER in text
        and 'lastAction = "AckBeforeCommit"' in last_state
        and "ackReceived = TRUE" in last_state
        and re.search(r'status\s*\|->\s*"open"', last_state) is not None
        and re.search(r"canonical\s*\|->\s*\{\s*\}", last_state) is not None
    )
    return expected, "expected-mutant-counterexample" if expected else "unexpected-checker-outcome"


def obtain_jar(output, lock):
    jar = output / "tla2tools-1.7.4.jar"
    if jar.exists():
        data = jar.read_bytes()
    else:
        # Fixed official source from the committed lock; no runtime update.
        with urllib.request.urlopen(lock["url"], timeout=60) as response:
            data = response.read(16 * 1024 * 1024 + 1)
    if len(data) != lock["size_bytes"]:
        raise ValueError("TLC artifact length does not match the committed lock")
    if lock["digest_algorithm"] != "sha1":
        raise ValueError("Unsupported TLC lock algorithm")
    if hashlib.sha1(data).hexdigest() != lock["digest"]:
        raise ValueError("TLC artifact does not match the published SHA-1 pin")
    jar.write_bytes(data)
    return jar, sha256(data)


def check(kind, config_name, jar, output):
    work = output / kind
    work.mkdir(parents=True, exist_ok=True)
    config = ROOT / "model" / config_name
    shutil.copyfile(MODEL, work / "StagedImport.tla")
    shutil.copyfile(config, work / "StagedImport.cfg")
    command = [
        "java", "-Xmx512m", "-cp", str(jar), "tlc2.TLC",
        "-workers", "1", "-fp", "0", "-config", "StagedImport.cfg",
        "StagedImport",
    ]
    timed_out = False
    try:
        completed = subprocess.run(
            command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", timeout=TIMEOUT_SECONDS,
            check=False,
        )
        returncode, text = completed.returncode, completed.stdout
    except subprocess.TimeoutExpired as error:
        timed_out = True
        returncode = None
        text = error.stdout or ""
        if isinstance(text, bytes):
            text = text.decode("utf-8", errors="replace")
        text += "\nStarTest: checker exceeded the resource timeout; result inconclusive.\n"
    log = work / "tlc.log"
    log.write_text(text, encoding="utf-8")
    passed, classification = classify(kind, returncode, text)
    result = {
        "case": kind, "passed": bool(passed), "classification": classification,
        "returncode": returncode, "timed_out": timed_out,
        "command": command, "log": str(log.relative_to(output)),
        "config_sha256": sha256(config.read_bytes()),
        "violated_invariants": re.findall(r"Invariant ([A-Za-z_][A-Za-z_0-9]*) is violated\.", text),
    }
    if timed_out:
        result["classification"] = "inconclusive-resource-limit"
    if kind == "mutant" and passed:
        trace = work / "ack-before-commit-counterexample.txt"
        trace.write_text(TRACE_HEADER + text.split(TRACE_HEADER, 1)[1], encoding="utf-8")
        result["counterexample"] = {
            "name": "ack-before-commit", "violated_invariant": "AckDurable",
            "trace": str(trace.relative_to(output)),
        }
    print(f"{kind}: {result['classification']} (TLC exit {returncode})")
    if not passed:
        print(text, file=sys.stderr)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts" / "tlc")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": "startest.tlc-run.v1", "started_at": now(),
        "assurance": "finite-model-exhaustive-safety",
        "claim_scope": "This abstract model only; no application or refinement proof.",
        "liveness_checked": False, "deadlock_checking": False,
        "bounds": {
            "workspaces": 1, "sessions_without_reuse": 1, "symbolic_new_record_ids": 2,
            "max_chunks": 2, "records_per_chunk": 1, "minimum_commit_records": 1,
            "max_crashes": 1, "max_restarts": 1,
        },
        "limits": {"seconds_per_check": TIMEOUT_SECONDS, "java_heap_mib": 512, "workers": 1},
        "model_sha256": sha256(MODEL.read_bytes()),
        "lock_sha256": sha256(LOCK.read_bytes()),
        "checks": [], "passed": False,
    }
    try:
        lock = json.loads(LOCK.read_text(encoding="utf-8"))
        jar, jar_sha256 = obtain_jar(output, lock)
        manifest["verifier"] = {
            "name": "TLC", "release": lock["version"], "url": lock["url"],
            "verified_published_digest": {"algorithm": "sha1", "value": lock["digest"]},
            "observed_artifact_sha256": jar_sha256,
        }
        version = subprocess.run(
            ["java", "-version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=15, check=True,
        )
        manifest["java_version_output"] = version.stdout
        for kind, config in [("normal", "StagedImport.cfg"), ("mutant", "StagedImport-mutant.cfg")]:
            manifest["checks"].append(check(kind, config, jar, output))
        manifest["passed"] = all(result["passed"] for result in manifest["checks"])
    except Exception as error:
        manifest["error"] = {"type": type(error).__name__, "message": str(error)}
        manifest["classification"] = "inconclusive-harness-or-tooling-error"
        print(f"TLC setup/check failed: {error}", file=sys.stderr)
    finally:
        manifest["finished_at"] = now()
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0 if manifest["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
