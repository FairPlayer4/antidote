-module(multiple_dcs_partial_rep_test).

-export([confirm/0, multiple_writes/4]).

-include_lib("eunit/include/eunit.hrl").

-define(HARNESS, (rt_config:get(rt_harness))).

%% Basic Partial replication tests
%% These tests don't use intercepts
%% Keys 1-10 only exist at DC 1
%% 11-20 at DC 2
%% 21-30 at DC 3
%% Each test writes a key that is replicated at a different
%% DC and checks that the keys and nodes can be read from anywhere

confirm() ->
    [Cluster1, Cluster2, Cluster3] = rt:build_clusters([1,1,1]),
    HeadCluster1 = hd(Cluster1),
    HeadCluster2 = hd(Cluster2),
    HeadCluster3 = hd(Cluster3),

    rt:wait_until_ring_converged(Cluster1),
    rt:wait_until_ring_converged(Cluster2),
    rt:wait_until_ring_converged(Cluster3),
    timer:sleep(500), %%TODO: wait for inter_dc_manager to be up
    {ok, DC1} = rpc:call(HeadCluster1, inter_dc_manager, start_receiver,[70001]),
    {ok, DC1Read} = rpc:call(HeadCluster1, inter_dc_manager, start_read_receiver,[80001]),
    {ok, DC1SafeSend} = rpc:call(HeadCluster1, inter_dc_manager, start_safe_send_receiver,[90001]),

    {ok, DC2} = rpc:call(HeadCluster2, inter_dc_manager, start_receiver,[70002]),
    {ok, DC2Read} = rpc:call(HeadCluster2, inter_dc_manager, start_read_receiver,[80002]),
    {ok, DC2SafeSend} = rpc:call(HeadCluster2, inter_dc_manager, start_safe_send_receiver,[90002]),

    {ok, DC3} = rpc:call(HeadCluster3, inter_dc_manager, start_receiver,[70003]),
    {ok, DC3Read} = rpc:call(HeadCluster3, inter_dc_manager, start_read_receiver,[80003]),
    {ok, DC3SafeSend} = rpc:call(HeadCluster3, inter_dc_manager, start_safe_send_receiver,[90003]),

    lager:info("Receivers start results ~p, ~p and ~p", [DC1, DC2, DC3]),
    lager:info("ReceiversRead start results ~p, ~p and ~p", [DC1Read, DC2Read, DC3Read]),
    lager:info("ReceiversSafeSend start results ~p, ~p and ~p", [DC1SafeSend, DC2SafeSend, DC3SafeSend]),

    ok = rpc:call(HeadCluster1, inter_dc_manager, add_list_dcs,[[DC2, DC3]]),
    ok = rpc:call(HeadCluster2, inter_dc_manager, add_list_dcs,[[DC1, DC3]]),
    ok = rpc:call(HeadCluster3, inter_dc_manager, add_list_dcs,[[DC1, DC2]]),

    ok = rpc:call(HeadCluster1, inter_dc_manager, add_list_read_dcs,[[DC2Read, DC3Read]]),
    ok = rpc:call(HeadCluster2, inter_dc_manager, add_list_read_dcs,[[DC1Read, DC3Read]]),
    ok = rpc:call(HeadCluster3, inter_dc_manager, add_list_read_dcs,[[DC1Read, DC2Read]]),

    ok = rpc:call(HeadCluster1, inter_dc_manager, add_list_safe_send_dcs,[[DC2SafeSend, DC3SafeSend]]),
    ok = rpc:call(HeadCluster2, inter_dc_manager, add_list_safe_send_dcs,[[DC1SafeSend, DC3SafeSend]]),
    ok = rpc:call(HeadCluster3, inter_dc_manager, add_list_safe_send_dcs,[[DC1SafeSend, DC2SafeSend]]),

    ok = rpc:call(HeadCluster1, inter_dc_manager, set_replication_keys, [dc1_test_normal]),
    ok = rpc:call(HeadCluster2, inter_dc_manager, set_replication_keys, [dc2_test_normal]),
    ok = rpc:call(HeadCluster3, inter_dc_manager, set_replication_keys, [dc3_test_normal]),

    simple_replication_test(Cluster1, Cluster2, Cluster3),
    parallel_writes_test(Cluster1, Cluster2, Cluster3),
    external_read_causality_test(Cluster1, Cluster2, Cluster3),
    pass.


%% This test will check to see that when a key is not replicated at a DC
%% and a read is performed though this DC for that key,
%% the value returned from the external DC is consistent with
%% the snapshot of the local DC
external_read_causality_test(Cluster1, Cluster2, Cluster3) ->
    Node1 = hd(Cluster1),
    Node2 = hd(Cluster2),
    Node3 = hd(Cluster3),
    Key = key15,
    
    WriteResult = rpc:call(Node1,
			   antidote, append,
			   [Key, riak_dt_gcounter, {increment, ucl}]),
    ?assertMatch({ok, _}, WriteResult),
    {ok,{_,_,CommitTime}}=WriteResult,
    
    WriteResult2 = rpc:call(Node2,
			    antidote, append,
			    [Key, riak_dt_gcounter, {increment, ucl}]),
    ?assertMatch({ok, _}, WriteResult2),
    
    %%Let the updates have time to propagate
    
    ReadResult = rpc:call(Node1,
			   antidote, clocksi_read,
			  [CommitTime, Key, riak_dt_gcounter]),
    {ok, {_,[ReadSet1],_} }= ReadResult,
    ?assertEqual(1, ReadSet1),
    lager:info("Done Read in Node1").

    



simple_replication_test(Cluster1, Cluster2, Cluster3) ->
    Node1 = hd(Cluster1),
    Node2 = hd(Cluster2),
    Node3 = hd(Cluster3),
    KeyList = [key5, key15, key25],
    

    list:foldl(fun(AKey, _Acc) ->
		      WriteResult1 = rpc:call(Node1,
					      antidote, append,
					      [AKey, riak_dt_gcounter, {increment, ucl}]),
		      ?assertMatch({ok, _}, WriteResult1),
		      WriteResult2 = rpc:call(Node1,
					      antidote, append,
					      [AKey, riak_dt_gcounter, {increment, ucl}]),
		      ?assertMatch({ok, _}, WriteResult2),
		      WriteResult3 = rpc:call(Node1,
					      antidote, append,
					      [Akey, riak_dt_gcounter, {increment, ucl}]),
		      ?assertMatch({ok, _}, WriteResult3),
		      {ok,{_,_,CommitTime}}=WriteResult3,
		      ReadResult = rpc:call(Node1, antidote, read,
					    [Akey, riak_dt_gcounter]),
		      ?assertEqual({ok, 3}, ReadResult),
		      
		      lager:info("Done append in Node1"),
		      ReadResult2 = rpc:call(Node3,
					     antidote, clocksi_read,
					     [CommitTime, Akey, riak_dt_gcounter]),
		      {ok, {_,[ReadSet1],_} }= ReadResult2,
		      ?assertEqual(3, ReadSet1),
		      lager:info("Done Read in Node3"),
		      ReadResult3 = rpc:call(Node2,
					     antidote, clocksi_read,
					     [CommitTime, Akey, riak_dt_gcounter]),
		      {ok, {_,[ReadSet2],_} }= ReadResult3,
		      ?assertEqual(3, ReadSet2),
		      
		      lager:info("Done first round of read, I am gonna append"),
		      WriteResult4= rpc:call(Node2,
                           antidote, clocksi_bulk_update,
					     [ CommitTime,
					       [{update, Akey, riak_dt_gcounter, {increment, ucl}}]]),
		      ?assertMatch({ok, _}, WriteResult4),
		      {ok,{_,_,CommitTime2}}=WriteResult4,
		      lager:info("Done append in Node2"),
		      WriteResult5= rpc:call(Node3,
					     antidote, clocksi_bulk_update,
					     [CommitTime2,
					      [{update, Akey, riak_dt_gcounter, {increment, ucl}}]]),
		      ?assertMatch({ok, _}, WriteResult5),
		      {ok,{_,_,CommitTime3}}=WriteResult5,
		      lager:info("Done append in Node3"),
		      lager:info("Done waiting, I am gonna read"),
		      
		      SnapshotTime =
			  CommitTime3,
		      ReadResult4 = rpc:call(Node1,
					     antidote, clocksi_read,
					     [SnapshotTime, Akey, riak_dt_gcounter]),
		      {ok, {_,[ReadSet4],_} }= ReadResult4,
		      ?assertEqual(5, ReadSet4),
		      lager:info("Done read in Node1"),
		      ReadResult5 = rpc:call(Node2,
					     antidote, clocksi_read,
					     [SnapshotTime,Akey, riak_dt_gcounter]),
		      {ok, {_,[ReadSet5],_} }= ReadResult5,
		      ?assertEqual(5, ReadSet5),
		      lager:info("Done read in Node2"),
		      ReadResult6 = rpc:call(Node3,
					     antidote, clocksi_read,
					     [SnapshotTime,Akey, riak_dt_gcounter]),
		      {ok, {_,[ReadSet6],_} }= ReadResult6,
		      ?assertEqual(5, ReadSet6)
	      end,
	      [], KeyList),
    pass.


parallel_writes_test(Cluster1, Cluster2, Cluster3) ->
    Node1 = hd(Cluster1),
    Node2 = hd(Cluster2),
    Node3 = hd(Cluster3),
    Pid = self(),
    %% WriteFun = fun(A,B,C,D) ->
    %%                    multiple_writes(A,B,C,D)
    %%            end,
    KeyList = [key6, key16, key26],
    

    list:foldl(fun(AKey, _Acc) ->
		      spawn(?MODULE, multiple_writes,[Node1,AKey, node1, Pid]),
		      spawn(?MODULE, multiple_writes,[Node2,AKey, node2, Pid]),
		      spawn(?MODULE, multiple_writes,[Node3,AKey, node3, Pid]),
		      Result = receive
				   {ok, CT1} ->
				       receive
					   {ok, CT2} ->
					       receive
						   {ok, CT3} ->
						       Time = dict:merge(fun(_K, T1,T2) ->
										 max(T1,T2)
									 end,
									 CT3, dict:merge(
										fun(_K, T1,T2) ->
											max(T1,T2)
										end,
										CT1, CT2)),
						       ReadResult1 = rpc:call(Node1,
									      antidote, clocksi_read,
									      [Time, AKey, riak_dt_gcounter]),
						       {ok, {_,[ReadSet1],_} }= ReadResult1,
						       ?assertEqual(15, ReadSet1),
						       ReadResult2 = rpc:call(Node2,
									      antidote, clocksi_read,
									      [Time, AKey, riak_dt_gcounter]),
						       {ok, {_,[ReadSet2],_} }= ReadResult2,
						       ?assertEqual(15, ReadSet2),
						       ReadResult3 = rpc:call(Node3,
									      antidote, clocksi_read,
									      [Time, AKey, riak_dt_gcounter]),
						       {ok, {_,[ReadSet3],_} }= ReadResult3,
						       ?assertEqual(15, ReadSet3),
						       lager:info("Parallel reads passed"),
						       pass
					       end
				       end
			       end,
		      ?assertEqual(Result, pass),
	      end,
	      [], KeyList),
    pass.


multiple_writes(Node, Key, Actor, ReplyTo) ->
    WriteResult1 = rpc:call(Node,
                            antidote, append,
                            [Key, riak_dt_gcounter, {increment, Actor}]),
    ?assertMatch({ok, _}, WriteResult1),
    WriteResult2 = rpc:call(Node,
                            antidote, append,
                            [Key, riak_dt_gcounter, {increment, Actor}]),
    ?assertMatch({ok, _}, WriteResult2),
    WriteResult3 = rpc:call(Node,
                            antidote, append,
                            [Key, riak_dt_gcounter, {increment, Actor}]),
    ?assertMatch({ok, _}, WriteResult3),
    WriteResult4 = rpc:call(Node,
                            antidote, append,
                            [Key, riak_dt_gcounter, {increment, Actor}]),
    ?assertMatch({ok, _}, WriteResult4),
    WriteResult5 = rpc:call(Node,
                            antidote, append,
                            [Key, riak_dt_gcounter, {increment, Actor}]),
    ?assertMatch({ok, _}, WriteResult5),
    {ok,{_,_,CommitTime}}=WriteResult5,
    ReplyTo ! {ok, CommitTime}.