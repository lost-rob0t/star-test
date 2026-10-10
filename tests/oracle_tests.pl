:- use_module('../oracle/staged_import').
:- begin_tests(staged_import).
open_read(read([],0,0,0,false,open,[a],true)).
committed_read(read([a],1,1,1,true,committed,[],false)).
test(ack_restart_durable) :-
    committed_read(R), check_trace([begin,chunk(a),commit,ack,crash,restart,R],true,X),
    assertion(X.verdict == pass).
test(precommit_invisibility) :-
    open_read(R), check_trace([begin,chunk(a),R],true,X), assertion(X.verdict == pass).
test(ack_before_commit_mutant) :-
    check_trace([begin,chunk(a),ack,crash,restart],true,X),
    assertion(X.verdict == fail), assertion(X.first_failure == 3).
test(unknown_branches) :-
    check_trace([begin,chunk(a),unknown_commit],false,X),
    assertion(X.verdict == inconclusive), assertion(X.possible_states == 2).
test(unknown_then_open_readback) :-
    open_read(R), check_trace([begin,chunk(a),unknown_commit,crash,restart,R],true,X),
    assertion(X.verdict == pass), assertion(X.possible_states == 1).
test(unknown_then_committed_readback) :-
    committed_read(R), check_trace([begin,chunk(a),unknown_commit,crash,restart,R],true,X),
    assertion(X.verdict == pass), assertion(X.possible_states == 1).
test(replay_no_effect) :-
    committed_read(R), check_trace([begin,chunk(a),replay_chunk(a),commit,ack,replay_commit,crash,restart,replay_commit,R],true,X),
    assertion(X.verdict == pass).
test(abort_isolation) :-
    check_trace([begin,chunk(a),abort,read([],0,0,0,false,aborted,[],false)],true,X),
    assertion(X.verdict == pass).
test(abort_cannot_commit) :-
    check_trace([begin,chunk(a),abort,commit],true,X), assertion(X.verdict == fail).
test(no_chunk_replay_after_commit) :-
    check_trace([begin,chunk(a),commit,replay_chunk(a)],true,X), assertion(X.verdict == fail).
test(partial_commit_rejected) :-
    check_trace([begin,chunk(a),commit,read([a],1,1,0,false,committed,[],false)],true,X),
    assertion(X.verdict == fail).
test(two_documents) :-
    check_trace([begin,chunk(a),chunk(b),commit,read([a,b],1,2,1,true,committed,[],false)],true,X),
    assertion(X.verdict == pass).
test(gap_cannot_pass) :-
    committed_read(R), check_trace([begin,chunk(a),commit,R],false,X), assertion(X.verdict == inconclusive).
test(no_final_read_inconclusive) :-
    check_trace([begin,chunk(a),commit,ack],true,X), assertion(X.verdict == inconclusive).
test(unknown_action,[throws(error(domain_error(trace_action,_),_))]) :-
    check_trace([made_up],true,_).
test(duplicate_read_ids,[throws(error(domain_error(trace_action,_),_))]) :-
    check_trace([read([a,a],1,2,1,true,committed,[],false)],true,_).
test(empty_commit_out_of_scope) :-
    check_trace([begin,commit],true,X), assertion(X.verdict == fail).
:- end_tests(staged_import).
:- initialization((run_tests -> halt(0) ; halt(1)), main).
