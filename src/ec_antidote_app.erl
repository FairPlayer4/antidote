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
-module(ec_antidote_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% PB Services
-define(SERVICES, [{ec_antidote_pb_txn, 109, 128}]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    case ec_antidote_sup:start_link() of
        {ok, Pid} ->
            ok = riak_core:register([{vnode_module, logging_vnode}]),
            ok = riak_core_node_watcher:service_up(logging, self()),
            %%EC layer

            ok = riak_core:register([{vnode_module, ec_vnode}]),
            ok = riak_core_node_watcher:service_up(ec, self()),

            ok = riak_core:register([{vnode_module, vectorclock_vnode}]),
            ok = riak_core_node_watcher:service_up(vectorclock, self()),

            ok = riak_core:register([{vnode_module, ec_materializer_vnode}]),
            ok = riak_core_node_watcher:service_up(ec_materializer, self()),

            ok = riak_core:register([{vnode_module, inter_dc_repl_vnode}]),
            ok = riak_core_node_watcher:service_up(interdcreplication, self()),
            ok = riak_core:register([{vnode_module, inter_dc_recvr_vnode}]),
            ok = riak_core_node_watcher:service_up(inter_dc_recvr, self()),

            ok = riak_core_ring_events:add_guarded_handler(ec_antidote_ring_event_handler, []),
            ok = riak_core_node_watcher_events:add_guarded_handler(ec_antidote_node_event_handler, []),
            ok = riak_api_pb_service:register(?SERVICES),
            {ok, Pid};
        {error, Reason} ->
            {error, Reason}
    end.

stop(_State) ->
    ok.