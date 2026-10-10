# StarTest

First bounded staged-import behavior oracle and finite-model validation slice.
See [the tracked plan](docs/PLAN.md) and [observation mapping](docs/OBSERVATIONS.md).

## Run

Requires SWI-Prolog and Python 3. No application installation is required for the
synthetic oracle suite:

    swipl -q -f none --no-packs -s tests/oracle_tests.pl
    python3 -m unittest discover -s tests -p '*_tests.py' -v
    swipl -q -f none --no-packs -s oracle/cli.pl < traces/ack-restart.json

The deliberate ack-before-commit trace must fail with exit 1 at event 3.
The uncertain-commit tests preserve both possible durable outcomes until observed.

## What this establishes

The oracle checks finite serial abstract traces. TLC checks the explicitly bounded
model. Neither establishes that Quasar, Tek9 or arbitrary software is correct.
Real application adapter, hard-kill/readback, canonical 0.10.1 fixture execution and
StarLang named-operation integration are not implemented in this pass.

CI checks out the exact PR head, retains test/model identities and evidence, and
has read-only repository permissions. Tool packages are Ubuntu-provided and recorded
per run; this is not yet a hermetic, digest-locked runtime closure.

Implementation is proposed in a draft PR for [issue #1](https://github.com/lost-rob0t/star-test/issues/1).
