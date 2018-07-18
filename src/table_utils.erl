%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 SyncFree Consortium.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%%%-------------------------------------------------------------------
%%% @author pedrolopes
%%% @doc An Antidote module that includes some utility functions for
%%%      table management.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(table_utils).
-include("querying.hrl").

%% API
-export([table/1,
         policy/1,
         columns/1,
         foreign_keys/1,
         indexes/1,
         column_names/1,
         primary_key_name/1,
         all_column_names/1,
         tables_metadata/1,
         table_metadata/2,
         is_primary_key/2,
         is_column/2,
         is_foreign_key/2,
         shadow_column_state/4]).

table(?TABLE(TName, _Policy, _Cols, _SCols, _Idx)) -> TName.

policy(?TABLE(_TName, Policy, _Cols, _SCols, _Idx)) -> Policy.

columns(?TABLE(_TName, _Policy, Cols, _SCols, _Idx)) -> Cols.

foreign_keys(?TABLE(_TName, _Policy, _Cols, SCols, _Idx)) -> SCols.

indexes(?TABLE(_TName, _Policy, _Cols, _SCols, Idx)) -> Idx.

column_names(Table) ->
    Columns = columns(Table),
    maps:get(?COLUMNS, Columns).

primary_key_name(Table) ->
    Columns = columns(Table),
    maps:get(?PK_COLUMN, Columns).

all_column_names(Table) ->
    TCols = column_names(Table),
    SCols = lists:map(fun(?FK(FKName, _FKType, _RefTable, _RefCol, _DelRule)) -> FKName end, foreign_keys(Table)),
    lists:append([['#st', '#version'], TCols, SCols]).

%% Metadata from tables are always read from the database;
%% Only individual table metadata is stored on cache.
tables_metadata(TxId) ->
    ObjKey = querying_utils:build_keys(?TABLE_METADATA_KEY, ?TABLE_DT, ?AQL_METADATA_BUCKET),
    [Meta] = querying_utils:read_keys(value, ObjKey, TxId),
    Meta.

table_metadata(TableName, TxId) ->
    case metadata_caching:get_key(TableName) of
        {error, _} ->
            Metadata = tables_metadata(TxId),
            TableNameAtom = querying_utils:to_atom(TableName),
            MetadataKey = {TableNameAtom, ?TABLE_NAME_DT},
            case proplists:get_value(MetadataKey, Metadata) of
                undefined -> [];
                TableMeta ->
                    ok = metadata_caching:insert_key(TableName, TableMeta),
                    TableMeta
            end;
        TableMetaObj ->
            TableMetaObj %% table metadata is a 'value' type object
    end.

is_primary_key(ColumnName, ?TABLE(_TName, _Policy, Cols, _FKeys, _Idx)) when is_map(Cols) ->
    ColList = maps:get(?PK_COLUMN, Cols),
    lists:member(ColumnName, ColList).

is_column(ColumnName, ?TABLE(_TName, _Policy, Cols, _FKeys, _Idx)) when is_map(Cols) ->
    ColList = maps:get(?COLUMNS, Cols),
    lists:member(ColumnName, ColList).

is_foreign_key(ColumnName, ?TABLE(_TName, _Policy, _Cols, FKeys, _Idx)) ->
    Aux = querying_utils:first_occurrence(
        fun(?FK(FkName, _FkType, _RefTable, _RefCol, _DelRule)) ->
            ColumnName == FkName
        end, FKeys),

    Aux =/= undefined.

% RecordData represents a single record, i.e. a list of tuples on the form:
% {{col_name, datatype}, value}
shadow_column_state(TableName, ShadowCol, RecordData, TxId) ->
    ?FK(FkName, FkType, _RefTable, _RefCol, _DelRule) = ShadowCol,
    ColName = {column_name(FkName), crdt_utils:type_to_crdt(FkType, undefined)},
    RefColValue = record_utils:lookup_value(ColName, RecordData),
    StateObjKey = querying_utils:build_keys({TableName, FkName}, ?SHADOW_COL_DT, ?AQL_METADATA_BUCKET),
    [ShColData] = querying_utils:read_keys(value, StateObjKey, TxId),
    RefColName = {RefColValue, ?SHADOW_COL_ENTRY_DT},
    State = record_utils:lookup_value(RefColName, ShColData),
    State.

%% ====================================================================
%% Internal functions
%% ====================================================================

column_name([{_TableName, ColName}]) -> ColName;
column_name(FkName) -> FkName.