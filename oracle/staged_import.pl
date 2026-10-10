:- module(staged_import, [initial_state/1, step/3, check_trace/3]).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(error)).

% Payload tokens are NOT StarIntel documents or a replacement schema.
% One fresh workspace/session, two distinct create operations, one process crash.
initial_state(s(absent, [], [], 0, 0, false, false, true, 0, false)).
% s(phase,staged,canonical,revision,journal,receipt,active,alive,crashes,ack)
step(s(absent,[],[],0,0,false,false,true,K,A), begin,
     s(open,[],[],0,0,false,true,true,K,A)).
step(s(open,S,[],0,0,false,true,true,K,A), chunk(Id),
     s(open,T,[],0,0,false,true,true,K,A)) :-
    memberchk(Id,[a,b]), \+ ord_memberchk(Id,S), ord_add_element(S,Id,T).
step(s(open,S,[],0,0,false,true,true,K,A), replay_chunk(Id),
     s(open,S,[],0,0,false,true,true,K,A)) :- ord_memberchk(Id,S).
step(s(open,S,[],0,0,false,true,true,K,A), commit,
     s(committed,[],S,1,1,true,false,true,K,A)) :- S \= [].
step(s(committed,[],C,1,1,true,false,true,K,_), ack,
     s(committed,[],C,1,1,true,false,true,K,true)).
step(s(committed,[],C,1,1,true,false,true,K,A), replay_commit,
     s(committed,[],C,1,1,true,false,true,K,A)).
step(s(open,_,[],0,0,false,true,true,K,A), abort,
     s(aborted,[],[],0,0,false,false,true,K,A)).
step(s(P,S,C,R,J,T,V,true,0,A), crash,
     s(P,S,C,R,J,T,V,false,1,A)).
step(s(P,S,C,R,J,T,V,false,1,A), restart,
     s(P,S,C,R,J,T,V,true,1,A)).
% An uncertain invocation may have stopped before or after durable promotion.
% Timeout does not mean abort. No hidden favourable transition is added elsewhere.
step(S, unknown_commit, S) :- S=s(open,_,[],0,0,false,true,true,_,_).
step(S, unknown_commit, T) :- step(S,commit,T).
step(S, read(Docs,Revision,Count,Journal,Receipt,Phase,Staged,Active), S) :-
    S=s(Phase,Staged,Docs,Revision,Journal,Receipt,Active,true,_,_),
    length(Docs,Count).

valid_action(begin).
valid_action(chunk(X)) :- memberchk(X,[a,b]).
valid_action(replay_chunk(X)) :- memberchk(X,[a,b]).
valid_action(commit).
valid_action(ack).
valid_action(replay_commit).
valid_action(abort).
valid_action(crash).
valid_action(restart).
valid_action(unknown_commit).
valid_action(read(D,R,N,J,T,P,S,A)) :-
    is_list(D), is_list(S), sort(D,D), sort(S,S),
    maplist(valid_id,D), maplist(valid_id,S),
    memberchk(R,[0,1]), memberchk(N,[0,1,2]), memberchk(J,[0,1]),
    memberchk(T,[true,false]), memberchk(A,[true,false]),
    memberchk(P,[absent,open,committed,aborted]).
valid_id(X) :- memberchk(X,[a,b]).

% Complete means no observation gap in the declared serial history.
% A final full read is required for a passing observed-trace verdict.
check_trace(Actions, Complete, Report) :-
    must_be(list,Actions), must_be(ground,Actions),
    ( memberchk(Complete,[true,false]) -> true ; domain_error(boolean,Complete) ),
    length(Actions,Length),
    ( Length =< 64 -> true ; resource_error(trace_length) ),
    ( maplist(valid_action,Actions) -> true ; domain_error(trace_action,Actions) ),
    initial_state(S), walk(Actions,[S],1,States,Failure),
    length(States,Possibilities),
    verdict(Failure,Actions,Complete,Verdict),
    Report=_{schema:"startest.trace-result.v1", assurance:"observed-trace-conformance",
             verdict:Verdict, possible_states:Possibilities, first_failure:Failure,
             steps:Length, complete:Complete,
             bounds:_{sessions:1,workspaces:1,document_ids:2,chunks:2,crashes:1,max_steps:64},
             application_execution:false,
             exclusions:["document-schema-validation","implementation-refinement-proof",
                         "power-loss-durability","event-delivery","concurrency"]}.
walk([],States,_,States,0).
walk([Action|Rest],States,I,Out,Failure) :-
    findall(T,(member(S,States),step(S,Action,T)),Bag), sort(Bag,Next),
    ( Next=[] -> Out=[], Failure=I
    ; J is I+1, walk(Rest,Next,J,Out,Failure) ).
verdict(F,_,_,fail) :- F > 0, !.
verdict(0,Actions,true,pass) :- last(Actions,read(_,_,_,_,_,_,_,_)), !.
verdict(0,_,_,inconclusive).
