:- use_module(staged_import).
:- use_module(library(http/json)).
:- use_module(library(pairs)).
:- initialization(main, main).

main :-
    catch((run -> true ; throw(error(domain_error(trace_envelope,input),_))),Error,(message_to_string(Error,Message),
        json_write_dict(current_output,_{schema:"startest.trace-result.v1",verdict:error,message:Message}),
        nl,halt(2))).
run :-
    read_string(current_input,65537,Raw), string_length(Raw,Size),
    ( Size =< 65536 -> true ; throw(error(resource_error(input_bytes),_)) ),
    setup_call_cleanup(open_string(Raw,Stream),
        ( json_read_dict(Stream,Input,[value_string_as(atom)]),
          read_string(Stream,_,Tail), normalize_space(string(""),Tail) ),
        close(Stream)),
    dict_pairs(Input,_,Pairs), pairs_keys(Pairs,Keys), sort(Keys,[complete,events]),
    maplist(event,Input.events,Actions),
    check_trace(Actions,Input.complete,Report),
    json_write_dict(current_output,Report,[width(0)]), nl,
    ( Report.verdict == fail -> halt(1) ; Report.verdict == inconclusive -> halt(3) ; halt(0) ).
event(D,A) :-
    dict_pairs(D,_,Pairs), pairs_keys(Pairs,Keys),
    event_keys(D.op,Expected), sort(Keys,Expected),
    convert(D.op,D,A), !.
event(D,_) :- throw(error(domain_error(trace_event,D),_)).
event_keys(Op,[op]) :- memberchk(Op,[begin,commit,ack,replay_commit,abort,crash,restart,unknown_commit]).
event_keys(Op,[id,op]) :- memberchk(Op,[chunk,replay_chunk]).
event_keys(read,[active,count,docs,journal,op,phase,receipt,revision,staged]).
convert(chunk,D,chunk(D.id)).
convert(replay_chunk,D,replay_chunk(D.id)).
convert(read,D,read(D.docs,D.revision,D.count,D.journal,D.receipt,D.phase,D.staged,D.active)).
convert(Op,_,Op) :- memberchk(Op,[begin,commit,ack,replay_commit,abort,crash,restart,unknown_commit]).
