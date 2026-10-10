# Bounded staged-import model

Run `bash scripts/check-tlc.sh` from any directory with Java and Python 3
available. The command downloads only the pinned official TLC artifact,
verifies the published SHA-1 and byte length, records the actual SHA-256,
and runs both configurations. Results and replayable TLC logs are written
under `artifacts/tlc` (override with `--output PATH`). No local model-checker
run is claimed merely because these files exist; hosted CI must execute it.

The normal configuration requires completed exhaustive finite-state checking
with no invariant error. The mutant must exit with TLC's safety-violation
status 12 and a state trace specifically violating `AckDurable`, with the
`AckBeforeCommit` action, successful received acknowledgement, and still-OPEN,
empty-canonical durable state. Syntax errors, missing Java, resource timeouts,
deadlocks, another invariant, and a generic nonzero exit do not satisfy the
negative control. The named counterexample is saved separately.

## Scope and mapping

One workspace, one non-reused session, two symbolic new record IDs, up to two
single-record chunks, commit after one or two chunks, at most one process
crash and one restart. Existing payloads/updates, validation and conflict
rejection, digest collisions, multiple sessions/workspaces, notifications,
expiration, postcommit mutations and host/power loss are excluded.

`db` is the abstract durable tuple. `Begin` and `Stage` each represent their
own completed transaction. `PrepareCommit` represents private tentative
work while durable state is still OPEN. `Promote` is the one outer-transaction
completion that changes canonical records, revision, canonical count,
journal, committed receipt, stage/chunk cleanup and active pointer together.
Crash/restart discard the processing phase and undelivered reply but preserve
`db` and the external controller's received-ack/readback history. This bounded
transport abstraction drops replies still in flight at crash.

`chunkCount` represents accepted chunk count (concrete `acceptedThrough + 1`
while OPEN); payloads and digest metadata are abstracted by unique record
identity. Identical chunk replay is allowed while OPEN; committed replay
returns the original fixed operation/session identity and revision/count with
no durable effect. Both replay actions can repeat indefinitely in this finite
state graph. A timeout affects observer knowledge only. Reads record actual
abstract canonical state, including after restart; no assumption requires a
read or retry eventually to happen.

`aborted` is an abstraction label for completed durable cleanup plus retained
controller history. Quasar actually removes the session metadata; this model
does not claim an on-disk ABORTED tombstone. No transition reopens an aborted
session or aborts a committed import. The model has no durable COMMITTING state.

The controller-received success is distinct from enqueueing, sending and
logging. `ackReceived`, `ackReceipt` and `ackDocs` survive restart as observer
history. The mutant fabricates that success after preparation but before
promotion, which should immediately violate `AckDurable`; a later successful
commit cannot repair the already-observed safety violation.

This is exhaustive finite-model safety checking, not a proof about the Quasar
implementation, all inputs, all executions or liveness. Deadlock checking is
disabled deliberately; no fairness or eventual-recovery assumption is added.
Application traces need their own documented observation mapping and verdict.
There is no step-depth truncation or state-space constraint hiding longer
finite-state behaviors; repetition is explored as cycles.

## Relation to the bounded Prolog oracle

The Prolog trace vocabulary uses coarser observation steps. Its `commit`
corresponds to `PrepareCommit` followed by `Promote`; `ack` corresponds to
`SendReply` followed by `ReceiveReply`. Its `unknown_commit` branches to either
`PrepareCommit` plus `RollbackPrepared`, or `PrepareCommit` plus `Promote`
without an observed successful reply. A later retry can resolve the outcome.
Additional private preparation, send, timeout and rollback phases stutter
under the durable-state projection except at their explicit observed event.
`Begin`, `Stage`, `Abort`, `ReplayChunk`, `ReplayCommit`, `Crash`, `Restart`
and canonical readback have the corresponding bounded abstract meanings.

This is an explicit mapping convention for the first slice, not a mechanically
proved refinement between the Prolog checker, this model and an application.
The trace checker and finite-model result retain separate assurance labels.

## Sources

- Observation/transaction mapping reviewed at the pinned research revision:
  https://github.com/lost-rob0t/starintel-auto-research/blob/2932fbb0d0b39efe8b86b56d1c181df28cadc0eb/roam/research/star-test/STARTEST-RESEARCH-000-formal-validation.org
- Official TLC 1.7.4 release and published SHA-1:
  https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4
- Official artifact metadata (upstream SHA-256 field is null):
  https://api.github.com/repos/tlaplus/tlaplus/releases/assets/184694200
- Exact safety exit status and invariant-message formats:
  https://github.com/tlaplus/tlaplus/blob/v1.7.4/tlatools/org.lamport.tlatools/src/tlc2/output/EC.java
  https://github.com/tlaplus/tlaplus/blob/v1.7.4/tlatools/org.lamport.tlatools/src/tlc2/output/MP.java

The upstream SHA-1 is a legacy integrity check. The run's recorded SHA-256 is
computed from downloaded bytes, not misrepresented as an upstream-published
SHA-256 or independent supply-chain attestation.
