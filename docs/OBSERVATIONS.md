# Bounded observation contract

The SWI relation accepts a serial, complete, instrumented abstract history when
there exists a model execution explaining every event. This is trace conformance,
not universal implementation refinement. The CLI takes JSON data only; no caller
goal, source path or executable text is evaluated.

- begin: durable OPEN metadata and active pointer; canonical state unchanged.
- chunk(id): durable acceptance of one distinct symbolic create; id is a or b.
- replay_chunk(id): matching previously accepted chunk while OPEN; no state effect.
- commit: observed atomic outer transaction completion. In one step, publish all
  staged IDs, increment revision once, set count/journal/receipt, delete staging,
  clear active. No stable COMMITTING state.
- ack: controller receives successful commit response; requires durable commit.
- unknown_commit: invocation outcome unknown, permitting either precommit or
  postcommit state. Timeout does not imply rollback or abort. Subsequent readback
  narrows the set; missing evidence is never silently replaced by a commit.
- replay_commit: existing committed receipt; no durable effect or event assertion.
- abort: completed cleanup of open session, no canonical effect. The aborted phase
  is observer history, NOT an on-disk Quasar tombstone.
- crash/restart: discard process availability, preserve durable tuple and observer
  ack; one crash budget. Does not model power loss.
- read: full quiescent logical snapshot with exact canonical/staged ID sets,
  revision, canonical count, import-journal cardinality, receipt and active pointer.

A complete trace ending in a full read can pass; absent final read or declared gaps
remain inconclusive. No reachable state is fail even when evidence is incomplete:
the supplied events are already contradictory. Malformed/unsupported input is error.
Empty imports, duplicate/update operations, conflicting chunks, cleanup failures,
TTL, arbitrary retries, multiple workspaces and unbounded histories are out of scope.
A trace rejected at the model boundary is not automatically an application bug:
the adapter must establish this profile before interpreting a verdict.

CLI statuses: 0 pass, 1 fail, 2 malformed/error, 3 inconclusive.
Report application_execution=false is mandatory for these synthetic CLI examples.
Real adapter evidence/reporting is intentionally not yet implemented.
