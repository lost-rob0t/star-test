--------------------------- MODULE StagedImport ---------------------------
EXTENDS Naturals, FiniteSets

CONSTANTS RecordIds, FaultyAck

ASSUME /\ Cardinality(RecordIds) = 2
       /\ FaultyAck \in BOOLEAN

\* One workspace and one non-reused session. Records are two symbolic NEW
\* IDs; payloads, validation, updates, revision conflicts and events are out
\* of scope. A chunk contains one previously unstaged record, so at most two
\* chunks are accepted. Commit requires one or two records (never empty).
\* "aborted" denotes completed cleanup plus retained observer history; the
\* concrete Quasar store deletes session metadata, not an ABORTED tombstone.

\* Same-shaped record sentinel: TLC cannot compare records with strings.
NoReceipt == [session |-> "none", operation |-> "none", revision |-> 0, count |-> 0]
Receipt(n) == [session |-> "session-1", operation |-> "commit-1",
               revision |-> 1, count |-> n]
Receipts == {Receipt(n) : n \in 1..2}

DBType == [status : {"absent", "open", "committed", "aborted"},
           staged : SUBSET RecordIds, canonical : SUBSET RecordIds,
           chunkCount : 0..2, revision : 0..1, count : 0..2,
           journal : SUBSET Receipts, receipt : Receipts \cup {NoReceipt},
           active : BOOLEAN]

EmptyDB == [status |-> "absent", staged |-> {}, canonical |-> {},
            chunkCount |-> 0, revision |-> 0, count |-> 0,
            journal |-> {}, receipt |-> NoReceipt, active |-> FALSE]

ReadbackType == [observed : BOOLEAN, afterRestart : BOOLEAN,
                 acked : BOOLEAN, docs : SUBSET RecordIds,
                 revision : 0..1, count : 0..2]
EmptyReadback == [observed |-> FALSE, afterRestart |-> FALSE,
                  acked |-> FALSE, docs |-> {}, revision |-> 0, count |-> 0]

VARIABLES db, previousDB, alive, crashCount, restartCount, phase,
          pendingReply, clientOutcome, ackReceived, ackReceipt, ackDocs,
          readback, lastAction

lifecycle == <<alive, crashCount, restartCount>>
acknowledgement == <<ackReceived, ackReceipt, ackDocs>>
vars == <<db, previousDB, lifecycle, phase, pendingReply, clientOutcome,
          acknowledgement, readback, lastAction>>

\* previousDB and lastAction are bounded checking auxiliaries, not storage.
Step(label, nextDB) == /\ db' = nextDB
                       /\ previousDB' = db
                       /\ lastAction' = label

Init == /\ db = EmptyDB
        /\ previousDB = EmptyDB
        /\ alive = TRUE
        /\ crashCount = 0
        /\ restartCount = 0
        /\ phase = "idle"
        /\ pendingReply = NoReceipt
        /\ clientOutcome = "idle"
        /\ ackReceived = FALSE
        /\ ackReceipt = NoReceipt
        /\ ackDocs = {}
        /\ readback = EmptyReadback
        /\ lastAction = "Init"

\* Begin and every accepted chunk are separate durable transactions.
Begin == /\ alive /\ phase = "idle" /\ db.status = "absent"
         /\ Step("Begin", [db EXCEPT !.status = "open", !.active = TRUE])
         /\ UNCHANGED <<lifecycle, phase, pendingReply, clientOutcome,
                         acknowledgement, readback>>

Stage(record) ==
    /\ alive /\ phase = "idle" /\ db.status = "open"
    /\ record \in RecordIds \ db.staged
    /\ Step("Stage", [db EXCEPT !.staged = @ \cup {record},
                                !.chunkCount = @ + 1])
    /\ UNCHANGED <<lifecycle, phase, pendingReply, clientOutcome,
                    acknowledgement, readback>>

\* Only an identical already-accepted chunk can replay while OPEN.
\* The bounded identity abstraction assumes no chunk-digest collision.
ReplayChunk(record) ==
    /\ alive /\ phase = "idle" /\ db.status = "open"
    /\ record \in db.staged
    /\ Step("ReplayChunk", db)
    /\ UNCHANGED <<lifecycle, phase, pendingReply, clientOutcome,
                    acknowledgement, readback>>

\* Transaction-private preparation leaves durable OPEN intact. Crashing
\* here discards the tentative work. There is no durable COMMITTING state.
PrepareCommit ==
    /\ alive /\ phase = "idle" /\ db.status = "open" /\ db.staged # {}
    /\ Step("PrepareCommit", db)
    /\ phase' = "prepared" /\ clientOutcome' = "pending"
    /\ UNCHANGED <<lifecycle, pendingReply, acknowledgement, readback>>

\* Outer transaction completion is the single promotion linearization.
\* Canonical records, revision/count, journal, receipt, stage/chunk cleanup
\* and active-pointer cleanup become durable together.
Promote ==
    /\ alive /\ phase = "prepared" /\ db.status = "open"
    /\ LET docs == db.staged
           n == Cardinality(docs)
       IN Step("Promote", [db EXCEPT !.status = "committed",
                                     !.canonical = docs, !.revision = 1,
                                     !.count = n, !.journal = {Receipt(n)},
                                     !.receipt = Receipt(n), !.staged = {},
                                     !.chunkCount = 0, !.active = FALSE])
    /\ phase' = "committed"
    /\ UNCHANGED <<lifecycle, pendingReply, clientOutcome,
                    acknowledgement, readback>>

RollbackPrepared ==
    /\ alive /\ phase = "prepared" /\ db.status = "open"
    /\ Step("RollbackPrepared", db)
    /\ phase' = "idle" /\ clientOutcome' = "unknown"
    /\ UNCHANGED <<lifecycle, pendingReply, acknowledgement, readback>>

ReplayCommit ==
    /\ alive /\ phase = "idle" /\ db.status = "committed"
    /\ Step("ReplayCommit", db)
    /\ phase' = "committed" /\ clientOutcome' = "pending"
    /\ UNCHANGED <<lifecycle, pendingReply, acknowledgement, readback>>

SendReply ==
    /\ alive /\ phase = "committed" /\ db.status = "committed"
    /\ Step("SendReply", db)
    /\ phase' = "sent" /\ pendingReply' = db.receipt
    /\ UNCHANGED <<lifecycle, clientOutcome, acknowledgement, readback>>

\* The external controller, not enqueue/send/logging, observes success.
ReceiveReply ==
    /\ alive /\ phase = "sent" /\ pendingReply # NoReceipt
    /\ Step("ReceiveReply", db)
    /\ phase' = "idle" /\ pendingReply' = NoReceipt
    /\ clientOutcome' = "success" /\ ackReceived' = TRUE
    /\ ackReceipt' = pendingReply /\ ackDocs' = db.canonical
    /\ UNCHANGED <<lifecycle, readback>>

DropReply ==
    /\ alive /\ phase = "sent"
    /\ Step("DropReply", db)
    /\ phase' = "idle" /\ pendingReply' = NoReceipt
    /\ clientOutcome' = "unknown"
    /\ UNCHANGED <<lifecycle, acknowledgement, readback>>

\* Timeout changes knowledge only; it never means rollback or rejection.
Timeout ==
    /\ alive /\ clientOutcome = "pending"
    /\ Step("Timeout", db) /\ clientOutcome' = "unknown"
    /\ UNCHANGED <<lifecycle, phase, pendingReply, acknowledgement, readback>>

Abort ==
    /\ alive /\ phase = "idle" /\ db.status = "open"
    /\ Step("Abort", [db EXCEPT !.status = "aborted", !.staged = {},
                                !.chunkCount = 0, !.active = FALSE])
    /\ UNCHANGED <<lifecycle, phase, pendingReply, clientOutcome,
                    acknowledgement, readback>>

\* At most one abrupt process crash and one restart. Durable state and
\* controller observations survive; transaction/reply state is discarded.
\* Replies still in transit are abstracted as lost on crash, not delivered.
Crash ==
    /\ alive /\ crashCount = 0
    /\ Step("Crash", db)
    /\ alive' = FALSE /\ crashCount' = 1
    /\ phase' = "idle" /\ pendingReply' = NoReceipt
    /\ clientOutcome' = IF clientOutcome = "pending" THEN "unknown"
                        ELSE clientOutcome
    /\ UNCHANGED <<restartCount, acknowledgement, readback>>

Restart ==
    /\ ~alive /\ crashCount = 1 /\ restartCount = 0
    /\ Step("Restart", db)
    /\ alive' = TRUE /\ restartCount' = 1
    /\ UNCHANGED <<crashCount, phase, pendingReply, clientOutcome,
                    acknowledgement, readback>>

ReadCanonical ==
    /\ alive /\ Step("ReadCanonical", db)
    /\ readback' = [observed |-> TRUE, afterRestart |-> restartCount = 1,
                     acked |-> ackReceived, docs |-> db.canonical,
                     revision |-> db.revision, count |-> db.count]
    /\ UNCHANGED <<lifecycle, phase, pendingReply, clientOutcome,
                    acknowledgement>>

\* Deliberate negative control: receive a fabricated successful response
\* while promotion is only prepared and durable state is still OPEN.
AckBeforeCommit ==
    /\ FaultyAck /\ alive /\ phase = "prepared" /\ db.status = "open"
    /\ Step("AckBeforeCommit", db)
    /\ ackReceived' = TRUE /\ ackReceipt' = Receipt(Cardinality(db.staged))
    /\ ackDocs' = db.staged /\ clientOutcome' = "success"
    /\ UNCHANGED <<lifecycle, phase, pendingReply, readback>>

Next == \/ Begin
        \/ \E record \in RecordIds : Stage(record) \/ ReplayChunk(record)
        \/ PrepareCommit \/ Promote \/ RollbackPrepared \/ ReplayCommit
        \/ SendReply \/ ReceiveReply \/ DropReply \/ Timeout \/ Abort
        \/ Crash \/ Restart \/ ReadCanonical \/ AckBeforeCommit

TypeOK ==
    /\ db \in DBType /\ previousDB \in DBType
    /\ alive \in BOOLEAN /\ crashCount \in 0..1 /\ restartCount \in 0..1
    /\ restartCount <= crashCount
    /\ phase \in {"idle", "prepared", "committed", "sent"}
    /\ pendingReply \in Receipts \cup {NoReceipt}
    /\ clientOutcome \in {"idle", "pending", "success", "unknown"}
    /\ ackReceived \in BOOLEAN /\ ackReceipt \in Receipts \cup {NoReceipt}
    /\ ackDocs \subseteq RecordIds /\ readback \in ReadbackType
    /\ lastAction \in {"Init", "Begin", "Stage", "ReplayChunk",
                       "PrepareCommit", "Promote", "RollbackPrepared",
                       "ReplayCommit", "SendReply", "ReceiveReply",
                       "DropReply", "Timeout", "Abort", "Crash",
                       "Restart", "ReadCanonical", "AckBeforeCommit"}

StageLifecycle ==
    /\ (db.status = "open" =>
          db.active /\ db.chunkCount = Cardinality(db.staged))
    /\ (db.status # "open" =>
          ~db.active /\ db.staged = {} /\ db.chunkCount = 0)

PrecommitInvisible ==
    db.status # "committed" =>
        /\ db.canonical = {} /\ db.revision = 0 /\ db.count = 0
        /\ db.journal = {} /\ db.receipt = NoReceipt

AtomicPromotion ==
    db.status = "committed" =>
        /\ db.canonical # {} /\ db.revision = 1
        /\ db.count = Cardinality(db.canonical)
        /\ db.receipt = Receipt(db.count) /\ db.journal = {db.receipt}
        /\ db.staged = {} /\ db.chunkCount = 0 /\ ~db.active

AckDurable ==
    ackReceived =>
        /\ db.status = "committed" /\ ackReceipt = db.receipt
        /\ ackDocs = db.canonical /\ ackDocs # {}
        /\ db.revision = 1 /\ db.count = Cardinality(ackDocs)
        /\ db.journal = {ackReceipt}

AckedReadback ==
    readback.observed /\ readback.acked =>
        /\ readback.docs = ackDocs /\ readback.revision = 1
        /\ readback.count = Cardinality(ackDocs)

ReplayIdempotent ==
    lastAction \in {"ReplayChunk", "ReplayCommit"} => db = previousDB

CrashRecoveryPreservesDurability ==
    lastAction \in {"Crash", "Restart", "RollbackPrepared"} => db = previousDB

DurableReadback ==
    lastAction = "ReadCanonical" =>
        /\ readback.docs = db.canonical /\ readback.revision = db.revision
        /\ readback.count = db.count

\* Safety only. No fairness, liveness, power-loss, real-app refinement, or
\* universal durability claim follows from exhaustive checking this model.
Spec == Init /\ [][Next]_vars
=============================================================================
