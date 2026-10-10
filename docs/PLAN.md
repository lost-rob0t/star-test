# Issue #1: first implementation pass

Research: [reviewed design](https://github.com/lost-rob0t/starintel-auto-research/blob/2932fbb0d0b39efe8b86b56d1c181df28cadc0eb/roam/research/star-test/STARTEST-RESEARCH-000-formal-validation.org).
Implementation tracking: https://github.com/lost-rob0t/star-test/issues/1

1. Bootstrap minimal main solely to permit a reviewable feature branch.
2. Implement bounded executable oracle, structured data-only CLI and regressions.
3. Implement corresponding finite TLC safety model and deliberate mutant.
4. Execute exact-head hosted CI; inspect checker output, not merely process exit.
5. Keep this a draft PR. Do not merge or enable auto-merge.

## Scope and exclusions

One fresh workspace/session, two distinct symbolic create IDs, one accepted single-ID
chunk per ID, at most one crash/restart. Payload semantics and StarIntel validation
are deliberately outside this abstraction. Only canonical 0.10.1 is in project scope;
there is no new StarIntel schema or fabricated document fixture.

Quasar: 9079604f766990db7f9b8998705862c4fa914c45.
Tek9: ca24ef35ea6877420cbca057dd7fb702fe29a740.
StarLang research pin: fa1c8f4fb0590526c39aa3e9bc4a7e6eac30bea7.

## Real application adapter: NOT IMPLEMENTED in this pass

The pinned [existing persistence runner](https://github.com/lost-rob0t/quasar/blob/9079604f766990db7f9b8998705862c4fa914c45/scripts/test-wireless-persistence)
resolves user-local Quicklisp paths and runs graceful write/read processes.
The [standalone test](https://github.com/lost-rob0t/quasar/blob/9079604f766990db7f9b8998705862c4fa914c45/control-plane/tests/standalone/wireless-import-persistence.lisp)
closes the store in unwind-protect. It supplies neither acknowledged hard-kill
boundaries nor an instrumented postcommit/pre-response barrier.
The reviewed research also establishes that existing promotion hooks are inside
the outer transaction. A trustworthy hard-kill experiment needs a pinned headless
Lisp dependency closure, the new postcommit barrier, consistent logical probes,
and an owning/reaping supervisor. None is pretended by a mock adapter.

Consequently CI in this PR validates only the oracle and finite model, NOT Quasar,
Tek9, canonical fixtures, a controlled real-process restart, or StarIntel conformance.
The executable abstract traces are synthetic test inputs, not application evidence.

## Next independently reviewable slices

- Lock headless Quasar/Tek9 dependency closure without substituting newer Tek9.
- Implement real Lisp adapter with canonical generated 0.10.1 authority, explicit
  pre/postcommit barriers and logical probe; Python supervisor owns/reaps processes.
- Differentially validate real traces against oracle and matching model catalog.
- Expand conflicts, update payloads, counts, multiple sessions and failure cleanup.
- Add daily/postmerge compatibility matrix, bounded fuzzing and completeness checks.
- Separately harden trusted deduplicating issue publisher; no test-job issue writes.
- Add StarLang named-operation bridge only after its operation contract is implemented.

No daily schedule, reusable application caller, publisher, Nix/Docker closure, or
certificate claiming application correctness is delivered by this first pass.
