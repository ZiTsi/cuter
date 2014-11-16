#!/usr/bin/env python
# -*- coding: utf-8 -*-

from cuter_global import *

JSON_TYPE_ANY = 0
JSON_TYPE_INT = 1
JSON_TYPE_FLOAT = 2
JSON_TYPE_ATOM = 3
JSON_TYPE_LIST = 4
JSON_TYPE_TUPLE = 5
JSON_TYPE_PID = 6
JSON_TYPE_REF = 7

CMD_LOAD_TRACE_FILE = 1
CMD_SOLVE = 2
CMD_GET_MODEL = 3
CMD_ADD_AXIOMS = 4
CMD_FIX_VARIABLE = 5
CMD_RESET_SOLVER = 6
CMD_STOP = 42

RSP_MODEL_DELIMITER_START = "model_start"
RSP_MODEL_DELIMITER_END = "model_end"

CONSTRAINT_TRUE = 1
CONSTRAINT_FALSE = 2

OP_PARAMS = 1
# OP_SPEC = 2
OP_GUARD_TRUE = 3
OP_GUARD_FALSE = 4
OP_MATCH_EQUAL_TRUE = 5
OP_MATCH_EQUAL_FALSE = 6
OP_TUPLE_SZ = 7
OP_TUPLE_NOT_SZ = 8
OP_TUPLE_NOT_TPL = 9
OP_LIST_NON_EMPTY = 10
OP_LIST_EMPTY = 11
OP_LIST_NOT_LST = 12
OP_SPAWN = 13
OP_SPAWNED = 14
OP_MSG_SEND = 15
OP_MSG_RECEIVE = 16
OP_MSG_CONSUME = 17
OP_UNFOLD_TUPLE = 18
OP_UNFOLD_LIST = 19

OP_ERLANG_HD_1 = 25
OP_ERLANG_TL_1 = 26
OP_ERLANG_IS_INTEGER_1 = 27

def is_constraint_kind(tp):
  return tp == CONSTRAINT_TRUE or tp == CONSTRAINT_FALSE

def is_interpretable(tp):
  xs = set([OP_SPAWN, OP_SPAWNED, OP_MSG_SEND, OP_MSG_RECEIVE, OP_MSG_CONSUME])
  return tp not in xs

def is_reversible_bif(tp):
  x = {
    OP_ERLANG_HD_1: True,
    OP_ERLANG_TL_1: True,
    OP_ERLANG_IS_INTEGER_1: False,
  }
  return x[tp] if tp in x else False

def is_reversible(tp, opcode):
  return is_constraint_kind(tp) or is_reversible_bif(opcode)
