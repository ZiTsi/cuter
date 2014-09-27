%% -*- erlang-indent-level: 2 -*-
%%------------------------------------------------------------------------------
-module(cuter_json).

-include("cuter_macros.hrl").

-export([command_to_json/2, term_to_json/1, json_to_term/1]).

-define(Q, $\").

-define(ENCODE(T, V), [$\{, ?Q, $t, ?Q, $:, T, $,, ?Q, $v, ?Q, $:, V, $\}]). %% {"t":T, "v":V}
-define(ENCODE_SYMBOLIC(V), [$\{, ?Q, $s, ?Q, $:, ?Q, V, ?Q, $\}]).          %% {"s":"V"}
-define(ENCODE_ALIAS(V), [$\{, ?Q, $l, ?Q, $:, ?Q, V, ?Q, $\}]).             %% {"l":"V"}
-define(ENCODE_DICT_ENTRY(K, V), [?Q, K, ?Q, $:, V]).    %% "K":V
-define(ENCODE_DICT(D), [?Q, $d, ?Q, $:, $\{, D, $\}]).  %% "d":{D}
-define(ENCODE_CMD(C, As), [$\{, ?Q, $c, ?Q, $:, C, $,, ?Q, $a, ?Q, $:, $\[, As, $\], $\}]). %% {"c":C, "a":[As]}

-define(IS_SIGN(C), (C =:= $-)).
-define(IS_DECIMAL_POINT(C), (C =:= $.)).
-define(IS_DIGIT(C), (C >= $0 andalso C =< $9)).
-define(IS_WHITESPACE(C), (C =:= $\s orelse C =:= $\t orelse C =:= $\r orelse C =:= $\n)).
-define(INC_OFFSET(Dec), Dec#decoder{offset = Dec#decoder.offset + 1}).
-define(PUSH(X, Dec), Dec#decoder{acc = [X | Dec#decoder.acc]}).


-record(decoder, {
  state = start,
  offset = 1,
  type = null,
  dict,
  replace_aliases,
  acc = []
}).


%% =============================================================
%% Exported JSON Encoding / Decoding functions
%% =============================================================

-spec command_to_json(integer(), [any()]) -> binary().
command_to_json(Cmd, Args) when is_list(Args) ->
  F = fun(X, Acc) -> [$,, json_encode(X) | Acc] end,
  [$, | Es] = lists:foldl(F, [], lists:reverse(Args)),
  C = ?ENCODE_CMD(integer_to_list(Cmd), Es),
  list_to_binary(C).

-spec term_to_json(any()) -> binary().
term_to_json(Term) ->
  list_to_binary(json_encode(Term)).

-spec json_to_term(binary()) -> any().
json_to_term(JSON) ->
  Tbl = ets:new(?MODULE, [set, protected]),
  Decoder = #decoder{dict = Tbl, replace_aliases = false},
  Obj = decode_object_with_sharing(JSON, Decoder),
  ets:delete(Tbl),
  Obj.

%% ==============================================================================
%% Decode JSON Terms
%% ==============================================================================

%% Decode an object that may have a dictionary of shared subterms
decode_object_with_sharing(JSON, Dec=#decoder{state = start}) ->
  case trim_whitespace(JSON) of
    <<$\{, Rest/binary>> ->
      R1 = decode_shared(Rest, Dec#decoder{state = start}),
      Bin = <<$\{, R1/binary>>,
      case decode_object(Bin, Dec#decoder{state = start, replace_aliases = true}) of
        {Obj, <<>>} -> Obj;
        _ -> parse_error(parse_error, Dec)
      end;
    _ ->
      parse_error(parse_error, Dec)
  end.

%% Decode an object without a dictionary of shared subterms
decode_object(JSON, Dec=#decoder{state = start}) ->
  case trim_whitespace(JSON) of
    <<$\{, Rest/binary>> ->
      decode_object(Rest, Dec#decoder{state = special_or_obj});
    _ ->
      parse_error(parse_error, Dec)
  end;
decode_object(JSON, Dec=#decoder{state = special_or_obj}) ->
  case trim_whitespace(JSON) of
    <<?Q, $l, ?Q, Rest/binary>> ->
      R1 = trim_whitespace(trim_separator(Rest, $:, Dec)),  %% Ensure we pass a trimmed JSON string
      {Obj, R2} = decode_alias(R1, Dec#decoder{offset = 1}),
      decode_object(R2, #decoder{state = endpoint, acc = [Obj]});
    <<?Q, $s, ?Q, Rest/binary>> ->
      R1 = trim_whitespace(trim_separator(Rest, $:, Dec)),  %% Ensure we pass a trimmed JSON string
      {Obj, R2} = decode_symbolic(R1, Dec#decoder{offset = 1}),
      decode_object(R2, #decoder{state = endpoint, acc = [Obj]});
    _ ->
      {Type, R1} = decode_type(JSON, Dec#decoder{state = start}),
      R2 = trim_separator(R1, $,, Dec),
      {Obj, R3} = decode_value(Type, R2, Dec#decoder{state = start}),
      decode_object(R3, #decoder{state = endpoint, acc = [Obj]})
  end;
decode_object(JSON, Dec=#decoder{state = endpoint, acc=[Obj]}) ->
  case trim_whitespace(JSON) of
    <<$\}, Rest/binary>> -> {Obj, Rest};
    _ -> parse_error(parse_error, Dec)
  end.

%% Decode an object that represents an alias for a shared subterm
decode_alias(JSON, Dec) ->
  O = Dec#decoder.offset,
  case JSON of
    <<?Q, Alias:O/binary, ?Q, Rest/binary>> ->
      {replace_alias(Alias, Dec), Rest};
    <<?Q, _:O/binary, _/binary>> ->
      decode_alias(JSON, ?INC_OFFSET(Dec));
    _ ->
      parse_error(parse_error, Dec)
  end.

replace_alias(Alias, #decoder{replace_aliases = false}) ->
  to_alias(Alias);
replace_alias(Alias, Dec=#decoder{replace_aliases = true}) ->
  Tbl = Dec#decoder.dict,
  case ets:lookup(Tbl, Alias) of
    [] -> parse_error({expected_alias, Alias}, Dec);
    [{Alias, Obj}] -> Obj
  end.

%% Decode an object that represents a symbolic variable
decode_symbolic(JSON, Dec) ->
  O = Dec#decoder.offset,
  case JSON of
    <<?Q, SymbVar:O/binary, ?Q, Rest/binary>> ->
      Symb = binary_to_list(SymbVar),
      {cuter_symbolic:deserialize(Symb), Rest};
    <<?Q, _:O/binary, _/binary>> ->
      decode_symbolic(JSON, ?INC_OFFSET(Dec));
    _ ->
      parse_error(parse_error, Dec)
  end.

%% Decode the dictionary of shared subterms
decode_shared(JSON, Dec=#decoder{state = start}) ->
  case trim_whitespace(JSON) of
    <<?Q, $d, ?Q, Rest/binary>> ->
      R = trim_separator(Rest, $:, Dec),
      decode_shared(R, Dec#decoder{state = start_dict});
    _ ->
      JSON  %% No dictionary found
  end;
decode_shared(JSON, Dec=#decoder{state = start_dict}) ->
  case trim_whitespace(JSON) of
    <<$\{, Rest/binary>> ->
      decode_shared(Rest, Dec#decoder{state = key, offset = 1});
    _ ->
      parse_error(parse_error, Dec)
  end;
decode_shared(JSON, Dec=#decoder{state = key}) ->
  O = Dec#decoder.offset,
  case trim_whitespace(JSON) of
    <<?Q, Key:O/binary, ?Q, Rest/binary>> ->
      R = trim_separator(Rest, $:, Dec),
      {Obj, Rem} = decode_object(R, Dec#decoder{state = start, offset = 1}),
      ets:insert(Dec#decoder.dict, {Key, Obj}),
      decode_shared(Rem, Dec#decoder{state = next_or_end});
    <<?Q, _:O/binary, _/binary>> ->
      decode_shared(JSON, ?INC_OFFSET(Dec));
    _ ->
      parse_error(parse_error, Dec)
  end;
decode_shared(JSON, Dec=#decoder{state = next_or_end}) ->
  case trim_whitespace(JSON) of
    <<$\}, Rest/binary>> ->
      expand_shared(Dec#decoder.dict),  %% 2nd pass to expand the aliases
      trim_separator(Rest, $,, Dec);
    <<$,, Rest/binary>>  ->
      decode_shared(Rest, Dec#decoder{state = key, offset = 1});
    _ ->
      parse_error(parse_error, Dec)
  end.

%% 2nd pass of the shared subterms to expand the nested aliases
expand_shared(Tbl) ->
  KVs = ets:tab2list(Tbl),
  F = fun({K, V}) ->
    E = expand_term(Tbl, V),
    ets:insert(Tbl, {K, E})
  end,
  lists:foreach(F, KVs).

expand_term(Tbl, Term) ->
  case is_alias(Term) of 
    false ->
      expand_concrete_term(Tbl, Term);
    true  ->
      K = from_alias(Term),
      [{K, V}] =  ets:lookup(Tbl, K),
      E = expand_term(Tbl, V),
      ets:insert(Tbl, {K, E}),
      E
  end.

expand_concrete_term(Tbl, Term) when is_list(Term) ->
  [expand_term(Tbl, T) || T <- Term];
expand_concrete_term(Tbl, Term) when is_tuple(Term) ->
  Ts = tuple_to_list(Term),
  list_to_tuple([expand_term(Tbl, T) || T <- Ts]);
expand_concrete_term(_Tbl, Term) -> Term.


%% Decode the type of an object
decode_type(JSON, Dec=#decoder{state = start}) ->
  case trim_whitespace(JSON) of
    <<?Q, $t, ?Q, Rest/binary>> ->
      R = trim_whitespace(trim_separator(Rest, $:, Dec)),  %% Ensure we pass a trimmed JSON string
      decode_type(R, Dec#decoder{state = type, acc = []});
    _ ->
      parse_error(parse_error, Dec)
  end;
decode_type(JSON, Dec=#decoder{state = type}) ->
  case JSON of
    <<I, Rest/binary>> when ?IS_DIGIT(I) ->
      decode_type(Rest, ?PUSH(I, Dec));
    _ ->
      Type = list_to_integer(lists:reverse(Dec#decoder.acc)),
      {Type, JSON}
  end.

%% Decode the value of an object
decode_value(Type, JSON, Dec=#decoder{state = start}) ->
  case trim_whitespace(JSON) of
    <<?Q, $v, ?Q, Rest/binary>> ->
      R = trim_whitespace(trim_separator(Rest, $:, Dec)),  %% Ensure we pass a trimmed JSON string
      decode_value(Type, R, Dec#decoder{state = value_start, acc = []});
    _ ->
      parse_error(parse_error, Dec)
  end;
decode_value(?JSON_TYPE_INT, JSON, Dec=#decoder{state = value_start})   -> decode_int(JSON, Dec);
decode_value(?JSON_TYPE_FLOAT, JSON, Dec=#decoder{state = value_start}) -> decode_float(JSON, Dec);
decode_value(?JSON_TYPE_ATOM, JSON, Dec=#decoder{state = value_start})  -> decode_atom(JSON, Dec);
decode_value(?JSON_TYPE_LIST, JSON, Dec=#decoder{state = value_start})  -> decode_list(JSON, Dec);
decode_value(?JSON_TYPE_TUPLE, JSON, Dec=#decoder{state = value_start}) -> decode_tuple(JSON, Dec).

%% Decode an integer
decode_int(JSON, Dec=#decoder{state = value_start}) ->
  case JSON of
    <<I, Rest/binary>> when ?IS_DIGIT(I); ?IS_SIGN(I) ->
      decode_int(Rest, ?PUSH(I, Dec));
    _ ->
      I = list_to_integer(lists:reverse(Dec#decoder.acc)),
      {I, JSON}
  end.

%% Decode a float
decode_float(JSON, Dec=#decoder{state = value_start}) ->
  case JSON of
    <<I, Rest/binary>> when ?IS_DIGIT(I); ?IS_SIGN(I); ?IS_DECIMAL_POINT(I) ->
      decode_float(Rest, ?PUSH(I, Dec));
    _ ->
      F = list_to_float(lists:reverse(Dec#decoder.acc)),
      {F, JSON}
  end.

%% Decode a list
decode_list(JSON, Dec=#decoder{state = value_start}) ->
  case trim_whitespace(JSON) of
    <<$\[, $\], Rest/binary>> ->
      {[], Rest};
    <<$\[, Rest/binary>> ->
      {Obj, Rem} = decode_object(Rest, Dec#decoder{state = start}),
      decode_list(Rem, Dec#decoder{state = value_next_or_end, acc = [Obj]});
    _ ->
      parse_error(parse_error, Dec)
  end;
decode_list(JSON, Dec=#decoder{state = value_next_or_end}) ->
  case trim_whitespace(JSON) of
    <<$\], Rest/binary>> ->
      {lists:reverse(Dec#decoder.acc), Rest};
    <<$,, Rest/binary>> ->
      {Obj, Rem} = decode_object(Rest, Dec#decoder{state = start}),
      decode_list(Rem, ?PUSH(Obj, Dec));
    _ ->
      parse_error(parse_error, Dec)
  end.

%% Decode a tuple
decode_tuple(JSON, Dec=#decoder{state = value_start}) ->
  {L, Rem} = decode_list(JSON, Dec#decoder{state = value_start}),
  {list_to_tuple(L), Rem}.

%% Decode an atom
decode_atom(JSON, Dec=#decoder{state = value_start}) ->
  case trim_whitespace(JSON) of
    <<$\[, Rest/binary>> ->
      decode_atom(Rest, Dec#decoder{state = value_next_or_end, acc = []});
    _ ->
      parse_error(parse_error, Dec)
  end;
decode_atom(JSON, Dec=#decoder{state = value_next_or_end}) ->
  case trim_whitespace(JSON) of
    <<I, Rest/binary>> when ?IS_DIGIT(I); I =:= $, ->
      decode_atom(Rest, ?PUSH(I, Dec));
    <<$\], Rest/binary>> ->
      Ts = string:tokens(lists:reverse(Dec#decoder.acc), ","),
      A = list_to_atom([list_to_integer(L) || L <- Ts]),
      {A, Rest};
    _ ->
      parse_error(parse_error, Dec)
  end.


%% Helpful functions for trimming the JSON binary string
trim_whitespace(JSON) ->
  case JSON of
    <<C, Rest/binary>> when ?IS_WHITESPACE(C) -> trim_whitespace(Rest);
    _ -> JSON
  end.

trim_separator(JSON, S, Dec) ->
  case trim_whitespace(JSON) of
    <<S, Rest/binary>> -> Rest;
    _ -> parse_error({expected_separator, S}, Dec)
  end.

%% Wrapper for raising parsing errors
parse_error(Error, Decoder) ->
  ets:delete(Decoder#decoder.dict),
  throw(Error).

%% Handle the representation of aliases
to_alias(X) -> {'__JSON_alias', X}.
from_alias({'__JSON_alias', X}) -> X.

is_alias({'__JSON_alias', _X}) -> true;
is_alias(_) -> false.


%% ==============================================================================
%% Encode Terms to JSON
%% ==============================================================================

json_encode(Term) ->
  case cuter_symbolic:is_symbolic(Term) of
    true  -> json_encode_symbolic(Term);
    false -> json_encode_concrete(Term)
  end.

%% Encode a symbolic value to JSON
json_encode_symbolic(Term) ->
  ?ENCODE_SYMBOLIC(cuter_symbolic:serialize(Term)).

%% Encode a non-symbolic value to JSON
json_encode_concrete(Term) ->
  Seen = ets:new(?MODULE, [set, protected]),
  Shared = ets:new(?MODULE, [set, protected]),
  scan_term(Term, Seen, Shared),
  T = encode_term(Term, Seen),
  Dict = encode_shared(Shared, Seen),
  merge_dict_term(Dict, T).

merge_dict_term([], T) -> T;
merge_dict_term(D, [$\{ | T]) ->
  PD = [$\{, D, $,],
  [PD | T].

%% 1st Pass of a Term to locate the shared subterms
scan_term([], _Seen, _Shared) -> ok;  %% Never remember the empty list
scan_term([H|T]=Term, Seen, Shared) ->
  case remember_term(Term, Seen, Shared) of
    true  -> ok;
    false ->
      scan_term(H, Seen, Shared),
      scan_term(T, Seen, Shared)
  end;
scan_term(Term, Seen, Shared) when is_tuple(Term) ->
  case remember_term(Term, Seen, Shared) of
    true  -> ok;
    false ->
      Ts = erlang:tuple_to_list(Term),
      lists:foreach(fun(T) -> scan_term(T, Seen, Shared) end, Ts)
  end;
scan_term(Term, Seen, Shared) ->
  case remember_term(Term, Seen, Shared) of
    true  -> ok;
    false -> ok
  end.

%% Update Seen and Shared dictionaries
remember_term(Term, Seen, Shared) ->
  case ets:lookup(Seen, Term) of
    [] ->
      ets:insert(Seen, {Term, init}),
      false;
    [{Term, init}] ->
      R = erlang:ref_to_list(erlang:make_ref()) -- "#Ref<>",
      ets:insert(Seen, {Term, R}),
      ets:insert(Shared, {R, Term}),
      true;
    [{Term, _R}] -> true
  end.

%% 2nd Pass of a Term to encode the term structure & the shared subterms

%% integer
encode_term(I, _Seen) when is_integer(I) ->
  ?ENCODE(integer_to_list(?JSON_TYPE_INT), integer_to_list(I));
%% float
encode_term(F, _Seen) when is_float(F) ->
  ?ENCODE(integer_to_list(?JSON_TYPE_FLOAT), float_to_list(F, [{decimals, 10}, compact]));
%% atom
encode_term(A, _Seen) when is_atom(A) ->
  F = fun(X, Acc) -> [$,, integer_to_list(X) | Acc] end,
  [$, | Es] = lists:foldl(F, [], lists:reverse(atom_to_list(A))),
  ?ENCODE(integer_to_list(?JSON_TYPE_ATOM), [$\[, Es, $\]]);
%% list
encode_term([], _Seen) ->
  ?ENCODE(integer_to_list(?JSON_TYPE_LIST), [$\[, $\]]);
encode_term(L, Seen) when is_list(L) ->
  F = fun(X, Acc) -> [$,, encode_maybe_shared_term(X, Seen) | Acc] end,
  [$, | Es] = lists:foldl(F, [], lists:reverse(L)),
  ?ENCODE(integer_to_list(?JSON_TYPE_LIST), [$\[, Es, $\]]);
%% tuple
encode_term({}, _Seen) ->
  ?ENCODE(integer_to_list(?JSON_TYPE_TUPLE), [$\[, $\]]);
encode_term(T, Seen) when is_tuple(T) ->
  F = fun(X, Acc) -> [$,, encode_maybe_shared_term(X, Seen) | Acc] end,
  L = tuple_to_list(T),
  [$, | Es] = lists:foldl(F, [], lists:reverse(L)),
  ?ENCODE(integer_to_list(?JSON_TYPE_TUPLE), [$\[, Es, $\]]);
encode_term(Term, _Seen) ->
  throw({unsupported_term, Term}).

encode_maybe_shared_term(T, Seen) when is_integer(T); is_float(T); is_atom(T); is_list(T); is_tuple(T) ->
  case is_shared(T, Seen) of
    false -> encode_term(T, Seen);
    {true, R} -> encode_term_alias(R)
  end;
encode_maybe_shared_term(Term, _Seen) ->
  throw({unsupported_term, Term}).

encode_term_alias(R) -> ?ENCODE_ALIAS(R).

is_shared(Term, Seen) ->
  case ets:lookup(Seen, Term) of
    [{Term, init}] -> false;
    [{Term, R}] -> {true, R};
    [] -> throw(assert_term_seen)
  end.

encode_shared(Shared, Seen) ->
  case ets:tab2list(Shared) of
    [] -> [];
    Ts ->
      F = fun({K, V}, Acc) -> [$,, ?ENCODE_DICT_ENTRY(K, encode_term(V, Seen)) | Acc] end,
      [$, | Es] = lists:foldl(F, [], Ts),
      ?ENCODE_DICT(Es)
  end.

