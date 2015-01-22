%% -*- erlang-indent-level: 2 -*-
%%------------------------------------------------------------------------------
-module(cuter_pp).

-include("include/cuter_macros.hrl").

-export([ mfa/3
        , input/1
        , exec_status/1
        , exec_info/1
        , path_vertex/1
        %% Verbose Scheduling
        , seed_execution/2
        , request_input/2
        , request_input_empty/1
        , request_input_success/4
        , store_execution/4
        , store_execution_fail/3
        , store_execution_success/4
        %% Verbose File/Folder Deletion
        , delete_file/2
        %% Verbose solving
        , sat/0
        , not_sat/0
        , model_start/0
        , model_end/0
        , received_var/1
        , received_val/1
        , port_closed/0
        , undecoded_msg/2
        , fsm_started/1
        , send_cmd/3
        %% Verbose merging
        , file_finished/1
        , set_goal/2
        , consume_msg/1
        , goal_already_achieved/1
        , search_goal_in_file/1
        , change_to_file/1
        , open_file/2
        , achieve_goal/2
        , open_pending_file/1
       ]).

-spec mfa(atom(), atom(), integer()) -> ok.
mfa(M, F, Ar) -> io:format("Testing ~p:~p/~p ...~n", [M, F, Ar]).

-spec input([any()]) -> ok.
input(As) when is_list(As) ->
  divider("="),
  io:format("INPUT~n"),
  input_parameters(As).

input_parameters([]) -> io:format("N/A~n");
input_parameters([H|T]) ->
  io:format("  ~p", [H]),
  lists:foreach(fun(X) -> io:format(", ~p", [X]) end, T),
  io:format("~n").

-spec exec_status(cuter_iserver:execution_status()) -> ok.
exec_status({success, {Cv, Sv}}) ->
  io:format("OK~n"),
  io:format("  CONCRETE: ~p~n", [Cv]),
  io:format("  SYMBOLIC: ~p~n", [Sv]);
exec_status({runtime_error, Node, Pid, {Cv, Sv}}) ->
  io:format("RUNTIME ERROR~n"),
  io:format("  NODE: ~p~n", [Node]),
  io:format("  PID: ~p~n", [Pid]),
  io:format("  CONCRETE: ~p~n", [Cv]),
  io:format("  SYMBOLIC: ~p~n", [Sv]);
exec_status({internal_error, Type, Node, Why}) ->
  io:format("INTERNAL ERROR~n"),
  io:format("  TYPE: ~p~n", [Type]),
  io:format("  NODE: ~p~n", [Node]),
  io:format("  REASON: ~p~n", [Why]).

-spec exec_info(orddict:orddict()) -> ok.
exec_info(Info) ->
  io:format("EXECUTION INFO~n"),
  F = fun({Node, Data}) ->
    io:format("  ~p~n", [Node]),
    lists:foreach(fun exec_info_data/1, Data)
  end,
  lists:foreach(F, Info).

exec_info_data({mapping, Ms}) ->
  io:format("    MAPPING~n"),
  lists:foreach(fun({Sv, Cv}) -> io:format("      ~p <=> ~p~n", [Sv, Cv]) end, Ms);
exec_info_data({monitor_logs, Logs}) ->
  io:format("    MONITOR LOGS~n"),
  io:format("      ~p~n", [Logs]);
exec_info_data({code_logs, Logs}) ->
  io:format("    CODE LOGS~n"),
  io:format("      ~p~n", [Logs]);
exec_info_data({int, Pid}) ->
  io:format("    INT~n"),
  io:format("      ~p~n", [Pid]);
%exec_info_data(Data) -> io:format("    ~p~n", [Data]).
exec_info_data(_) -> ok.

-spec path_vertex(cuter_analyzer:path_vertex()) -> ok.
path_vertex(Vertex) ->
  io:format("PATH VERTEX~n"),
  io:format("  ~p (~w)~n", [Vertex, length(Vertex)]).

divider(Divider) ->
  lists:foreach(fun(_) -> io:format(Divider) end, lists:seq(1,50)),
  io:format("~n").

%%
%% Verbose Scheduling
%%

-spec seed_execution(reference(), map()) -> ok.
-ifdef(VERBOSE_SCHEDULER).
seed_execution(Rf, Info) ->
  io:format("SEED EXECUTION~n"),
  io:format("  HANDLE~n"),
  io:format("    ~p~n", [Rf]),
  io:format("  STORED INFO~n"),
  io:format("    ~p~n", [Info]).
-else.
seed_execution(_Rf, _Info) -> ok.
-endif.


-spec request_input(queue:queue(), ets:tid()) -> ok.
-ifdef(VERBOSE_SCHEDULER).
request_input(Q, I) ->
  io:format("REQUEST INPUT~n"),
  io:format("  CURRENT QUEUE~n"),
  io:format("    ~p~n", [queue:to_list(Q)]),
  io:format("  ALL HANDLES~n"),
  {Handles, _} = lists:unzip(ets:tab2list(I)),
  io:format("    ~p~n", [Handles]).
-else.
request_input(_Q, _I) -> ok.
-endif.

-spec request_input_empty(ets:tid()) -> ok.
-ifdef(VERBOSE_SCHEDULER).
request_input_empty(I) ->
  io:format("UNABLE TO GENERATE A TESTCASE~n"),
  {Handles, _} = lists:unzip(ets:tab2list(I)),
  case Handles of
    [] -> ok;
    _ ->
      io:format("  [!!] HANDLES LEFT~n"),
      io:format("    ~p~n", [Handles])
  end.
-else.
request_input_empty(_I) -> ok.
-endif.

-spec request_input_success(reference(), [any()], queue:queue(), ets:tid()) -> ok.
-ifdef(VERBOSE_SCHEDULER).
request_input_success(Rf, Inp, Q, I) ->
  io:format("NEW INPUT SENT~n"),
  io:format("  HANDLE~n"),
  io:format("    ~p~n", [Rf]),
  io:format("  ARGS~n"),
  io:format("    ~p~n", [Inp]),
  io:format("  NEW QUEUE~n"),
  io:format("    ~p~n", [queue:to_list(Q)]),
  io:format("  ALL HANDLES~n"),
  {Handles, _} = lists:unzip(ets:tab2list(I)),
  io:format("    ~p~n", [Handles]).
-else.
request_input_success(_Rf, _Inp, _Q, _I) -> ok.
-endif.

-spec store_execution(reference(), map(), queue:queue(), ets:tid()) -> ok.
-ifdef(VERBOSE_SCHEDULER).
store_execution(Rf, Info, Q, I) ->
  io:format("STORE EXECUTION~n"),
  io:format("  HANDLE~n"),
  io:format("    ~p~n", [Rf]),
  io:format("  EXEC INFO~n"),
  io:format("    ~p~n", [Info]),
  io:format("  CURRENT QUEUE~n"),
  io:format("    ~p~n", [queue:to_list(Q)]),
  io:format("  ALL HANDLES~n"),
  {Handles, _} = lists:unzip(ets:tab2list(I)),
  io:format("    ~p~n", [Handles]).
-else.
store_execution(_Rf, _Info, _Q, _I) -> ok.
-endif.

-spec store_execution_fail(integer(), integer(), ets:tid()) -> ok.
-ifdef(VERBOSE_SCHEDULER).
store_execution_fail(N, Depth, I) ->
  io:format("WILL NOT STORE EXECUTION~n"),
  io:format("  NEXT REVERSIBLE COMMAND > DEPTH~n"),
  io:format("    ~p > ~p~n", [N, Depth]),
  io:format("  HANDLES LEFT~n"),
  {Handles, _} = lists:unzip(ets:tab2list(I)),
  io:format("    ~p~n", [Handles]).
-else.
store_execution_fail(_N, _D, _I) -> ok.
-endif.

-spec store_execution_success(integer(), integer(), queue:queue(), ets:tid()) -> ok.
-ifdef(VERBOSE_SCHEDULER).
store_execution_success(N, Depth, Q, I) ->
  io:format("EXECUTION STORED~n"),
  io:format("  NEXT REVERSIBLE COMMAND =< DEPTH~n"),
  io:format("    ~p >= ~p~n", [N, Depth]),
  io:format("  NEW QUEUE~n"),
  io:format("    ~p~n", [queue:to_list(Q)]),
  io:format("  ALL HANDLES~n"),
  {Handles, _} = lists:unzip(ets:tab2list(I)),
  io:format("    ~p~n", [Handles]).
-else.
store_execution_success(_N, _D, _Q, _I) -> ok.
-endif.

%%
%% Verbose File/Folder Deletion
%%

-spec delete_file(file:name(), boolean()) -> ok.
-ifdef(VERBOSE_FILE_DELETION).
delete_file(F, true) ->
  io:format("[DELETE] ~p (OK)~n", [F]);
delete_file(F, false) ->
  io:format("[DELETE] ~p (LEAVE INTACT)~n", [F]).
-else.
delete_file(_F, _Intact) -> ok.
-endif.

%%
%% Verbose solving
%%

-spec sat() -> ok.
-ifdef(VERBOSE_SOLVING).
sat() -> io:format("[SLV] (solving) SAT~n").
-else.
sat() -> ok.
-endif.

-spec not_sat() -> ok.
-ifdef(VERBOSE_SOLVING).
not_sat() -> io:format("[SLV] (solving) NOT SAT~n").
-else.
not_sat() -> ok.
-endif.

-spec model_start() -> ok.
-ifdef(VERBOSE_SOLVING).
model_start() -> io:format("[SLV] (generating_model) Beginning of the model~n").
-else.
model_start() -> ok.
-endif.

-spec model_end() -> ok.
-ifdef(VERBOSE_SOLVING).
model_end() -> io:format("[SLV] (expecting_var) End of the model~n").
-else.
model_end() -> ok.
-endif.

-spec received_var(cuter_symbolic:symbolic()) -> ok.
-ifdef(VERBOSE_SOLVING).
received_var(Var) -> io:format("[SLV] (expecting_var) Var: ~p~n", [Var]).
-else.
received_var(_Var) -> ok.
-endif.

-spec received_val(any()) -> ok.
-ifdef(VERBOSE_SOLVING).
received_val(Val) -> io:format("[SLV] (expecting_value) Val: ~p~n", [Val]).
-else.
received_val(_Val) -> ok.
-endif.

-spec port_closed() -> ok.
-ifdef(VERBOSE_SOLVING).
port_closed() -> io:format("[SLV] (finished) Port Closed~n").
-else.
port_closed() -> ok.
-endif.

-spec undecoded_msg(binary(), cuter_solver:state()) -> ok.
-ifdef(VERBOSE_SOLVING).
undecoded_msg(Msg, State) -> io:format("[SLV INFO] (~p) ~p~n", [State, Msg]).
-else.
undecoded_msg(_Msg, _State) -> ok.
-endif.

-spec fsm_started(port()) -> ok.
-ifdef(VERBOSE_SOLVING).
fsm_started(Port) -> io:format("[FSM] (idle) Started (Port ~p)~n", [Port]).
-else.
fsm_started(_Port) -> ok.
-endif.

-spec send_cmd(cuter_solver:state(), binary(), string()) -> ok.
-ifdef(VERBOSE_SOLVING).
send_cmd(State, Cmd, Descr) -> io:format("[FSM] (~p) ~p~n  ~p~n", [State, Descr, Cmd]).
-else.
send_cmd(_State, _Cmd, _Descr) -> ok.
-endif.

%%
%% Verbose Merging
%%

-spec file_finished(file:name()) -> ok.
-ifdef(VERBOSE_MERGING).
file_finished(File) -> io:format("[MERGE] Fully parsed ~p~n", [File]).
-else.
file_finished(_File) -> ok.
-endif.

-spec set_goal(cuter_merger:goal(), string()) -> ok.
-ifdef(VERBOSE_MERGING).
set_goal(Goal, Tp) -> io:format("[MERGE] (~p) Set Goal ~p~n", [Tp, Goal]).
-else.
set_goal(_Goal, _Tp) -> ok.
-endif.

-spec consume_msg(reference()) -> ok.
-ifdef(VERBOSE_MERGING).
consume_msg(Rf) -> io:format("[MERGE] (MSG CONSUME) ~p~n", [Rf]).
-else.
consume_msg(_Rf) -> ok.
-endif.

-spec goal_already_achieved(cuter_merger:goal()) -> ok.
-ifdef(VERBOSE_MERGING).
goal_already_achieved(Goal) -> io:format("[MERGE] Already achieved ~p~n", [Goal]).
-else.
goal_already_achieved(_Goal) -> ok.
-endif.

-spec search_goal_in_file(file:name()) -> ok.
-ifdef(VERBOSE_MERGING).
search_goal_in_file(File) -> io:format("[MERGE] Will look in ~p~n", [File]).
-else.
search_goal_in_file(_File) -> ok.
-endif.

-spec change_to_file(file:name()) -> ok.
-ifdef(VERBOSE_MERGING).
change_to_file(File) -> io:format("[MERGE] Changing to ~p~n", [File]).
-else.
change_to_file(_File) -> ok.
-endif.

-spec open_file(file:name(), [file:name()]) -> ok.
-ifdef(VERBOSE_MERGING).
open_file(File, Pending) ->
  io:format("[MERGE] Opening ~p~n", [File]),
  io:format("  Pending files~n"),
  io:format("    ~p~n", [Pending]).
-else.
open_file(_File, _Pending) -> ok.
-endif.

-spec achieve_goal(cuter_merger:goal(), cuter_merger:goal()) -> ok.
-ifdef(VERBOSE_MERGING).
achieve_goal(Goal, NextGoal) ->
  io:format("[MERGE] Achieved ~p~n", [Goal]),
  io:format("  Changing to ~p~n", [NextGoal]).
-else.
achieve_goal(_Goal, _NextGoal) -> ok.
-endif.

-spec open_pending_file(file:name()) -> ok.
-ifdef(VERBOSE_MERGING).
open_pending_file(File) -> io:format("[MERGE] Opening from pending ~p~n", [File]).
-else.
open_pending_file(_File) -> ok.
-endif.
