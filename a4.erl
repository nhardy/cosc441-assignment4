-module(a4).
-export([a4/0]).

topics() ->
    [topic1, topic2, topic3, topic4, topic5].

a4() ->
    Topics = topics(),
    Server = spawn_link(fun() ->
        server()
    end),

    NumAuctions = rand:uniform(5),

    AuctionTopicPairs = lists:map(fun (_) ->
        Topic = lists:nth(rand:uniform(length(Topics) - 1), Topics),
        io:fwrite("Spawning Auction with Topic: ~s~n", [Topic]),
        {spawn_link(fun () ->
            auction(Server, Topic)
        end), Topic}
    end, range(1, NumAuctions)),

    Server ! {init, AuctionTopicPairs},

    NumClients = 9 + rand:uniform(6),
    lists:foreach(fun (_) ->
        spawn_link(fun () ->
            client(Server)
        end)
    end, range(1, NumClients)),

    % TODO: spawn new Auctions and Clients
    spawnThings(Server),
    ok.

spawnThings(Server) ->
    spawnThings(Server, 10).

spawnThings(_, 0) ->
    ok;
spawnThings(Server, N) ->
    timer:sleep(rand:uniform(5) * 1000),
    NumAuctions = rand:uniform(5),
    lists:foreach(fun (_) ->
        spawn_link(fun () ->
            auction(Server)
        end)
    end, range(1, NumAuctions)),
    NumClients = rand:uniform(9 + rand:uniform(6)),
    lists:foreach(fun (_) ->
        spawn_link(fun () ->
            client(Server)
        end)
    end, range(1, NumClients)),
    spawnThings(Server, N - 1).

server() ->
    receive {init, AuctionTopicPairs} ->
        server(AuctionTopicPairs, [])
    end.

server(AuctionTopicPairs, ClientTopicsPairs) ->
    receive {msg, MsgType, Details} ->
        case MsgType of
            newAuction ->
                {Auction, Topic} = Details,
                lists:foreach(fun ({Client, Topics}) ->
                    IsClientMaybeInterested = lists:member(Topic, Topics),
                    if
                        IsClientMaybeInterested ->
                            Auction ! {msg, interestedClient, {Client}};
                        true ->
                            ok
                    end
                end, ClientTopicsPairs),
                server([{Auction, Topic}|AuctionTopicPairs], ClientTopicsPairs);

            subscribe ->
                {Client, Topics} = Details,
                lists:foreach(fun ({Auction, Topic}) ->
                    IsClientMaybeInterested = lists:member(Topic, Topics),
                    if
                        IsClientMaybeInterested ->
                            Auction ! {msg, interestedClient, {Client}};
                        true ->
                            ok
                    end
                end, AuctionTopicPairs),
                server(AuctionTopicPairs, [{Client, Topics}|ClientTopicsPairs]);

            unsubscribe ->
                {Client} = Details,
                server(AuctionTopicPairs, lists:filter(fun ({C, _}) ->
                    C /= Client
                end, ClientTopicsPairs))
        end
    end.

auction(Server) ->
    Auction = self(),
    AllTopics = topics(),
    Topic = lists:nth(rand:uniform(length(AllTopics)), AllTopics),
    Server ! {msg, newAuction, {Auction, Topic}},
    auction(Server, Topic).

auction(Server, Topic) ->
    Deadline = timeInMs() + 1000 + rand:uniform(2000),
    MinBid = rand:uniform(50),
    auction(Server, Topic, Deadline, MinBid, []).

auction(Server, Topic, Deadline, MinBid, ClientBidPairs) ->
    Auction = self(),
    IsPastDeadline = timeInMs() >= Deadline,
    if
        IsPastDeadline ->
            if
                length(ClientBidPairs) == 0 ->
                    ok;
                length(ClientBidPairs) == 1 ->
                    [{Winner, _}] = ClientBidPairs,
                    Winner ! {msg, wonAuction, {Auction, -1}},
                    ok;
                true ->
                    [{Winner, _}|[{_, NextHighestBid}|_]] = lists:sort(fun ({_, B1}, {_, B2}) ->
                        B1 =< B2
                    end, ClientBidPairs),
                    lists:foreach(fun ({Client, _}) ->
                        if
                            Client == Winner ->
                                Client ! {msg, wonAuction, {Auction, NextHighestBid}};
                            true ->
                                Client ! {msg, lostAuction, {Auction}}
                        end
                    end, ClientBidPairs),
                    ok
            end;
        true ->
            receive {msg, MsgType, Details} ->
                case MsgType of
                    interestedClient ->
                        {Client} = Details,
                        CurrentMinBid = lists:foldl(fun ({_, Bid}, Acc) ->
                            max(Acc, Bid + 1)
                        end, MinBid, ClientBidPairs),
                        Client ! {msg, auctionAvailable, {Auction, Topic, CurrentMinBid}},
                        auction(Server, Topic, Deadline, MinBid, [{Client, -1}|ClientBidPairs]);

                    bid ->
                        {Client, Bid} = Details,
                        CurrentMinBid = lists:foldl(fun ({_, B}, Acc) ->
                            max(Acc, B + 1)
                        end, MinBid, ClientBidPairs),
                        if
                            Bid >= CurrentMinBid ->
                                io:fwrite("Auction ~p received bid from Client ~p: ~B~n", [Auction, Client, Bid]),
                                lists:foreach(fun ({C, _}) ->
                                    C ! {msg, newBid, {Auction, Bid}}
                                end, ClientBidPairs),
                                auction(Server, Topic, Deadline, MinBid, lists:map(fun ({C, B}) ->
                                    if
                                        C == Client ->
                                            {C, Bid};
                                        true ->
                                            {C, B}
                                    end
                                end, ClientBidPairs));
                            true ->
                                auction(Server, Topic, Deadline, MinBid, ClientBidPairs)
                        end;

                    notInterested ->
                        {Client} = Details,
                        auction(Server, Topic, Deadline, MinBid, lists:filter(fun({C, _}) ->
                            C /= Client
                        end, ClientBidPairs))
                end
            after
                1000 ->
                    auction(Server, Topic, Deadline, MinBid, ClientBidPairs)
            end
    end.

client(Server) ->
    Client = self(),
    AllTopics = topics(),
    Topics = takeRandom(rand:uniform(length(AllTopics)), AllTopics),
    Server ! {msg, subscribe, {Client, Topics}},
    client(Server, Topics, []).

client(Server, Topics, AuctionTopicBidTuples) ->
    Client = self(),
    % TODO: Random loss of interest in Topics
    receive {msg, MsgType, Details} ->
        case MsgType of
            auctionAvailable ->
                {Auction, Topic, MinBid} = Details,
                IsInterested = rand:uniform(100) =< 67,
                if
                    IsInterested ->
                        Bid = MinBid + rand:uniform(5) - 1,
                        Auction ! {msg, bid, {Client, Bid}},
                        client(Server, Topics, [{Auction, Topic, Bid}|AuctionTopicBidTuples]);
                    true ->
                        Auction ! {msg, notInterested, {Client}},
                        client(Server, Topics, AuctionTopicBidTuples)
                end;
            newBid ->
                {Auction, CurrentBid} = Details,
                WasInterested = lists:member(Auction, lists:map(fun ({A, _, _}) ->
                    A
                end, AuctionTopicBidTuples)),
                if
                    WasInterested ->
                        OurBid = lists:foldl(fun (B, _) ->
                            B
                        end, -1, lists:filter(fun ({A, _, B}) ->
                            (A == Auction) and (B == CurrentBid)
                        end, AuctionTopicBidTuples)),
                        IsStillInterested = (OurBid == CurrentBid) or (rand:uniform(100) =< 99),
                        if
                            IsStillInterested ->
                                ShouldBid = OurBid == CurrentBid,
                                if
                                    ShouldBid ->
                                        NewBid = CurrentBid + rand:uniform(5),
                                        Auction ! {msg, bid, {Client, NewBid}},
                                        client(Server, Topics, lists:map(fun ({A, T, B}) ->
                                            if
                                                A == Auction ->
                                                    {A, T, NewBid};
                                                true ->
                                                    {A, T, B}
                                            end
                                        end, AuctionTopicBidTuples));
                                    true ->
                                        client(Server, Topics, AuctionTopicBidTuples)
                                end;
                            true ->
                                client(Server, Topics, lists:filter(fun ({A, _, _}) ->
                                    A /= Auction
                                end, AuctionTopicBidTuples))
                        end;
                    true ->
                        client(Server, Topics, lists:filter(fun ({A, _, _}) ->
                            A /= Auction
                        end, AuctionTopicBidTuples))
                end;
            wonAuction ->
                {Auction, NextHighestBid} = Details,
                io:fwrite("Client ~p won Auction ~p where the next highest bid was ~B~n", [Client, Auction, NextHighestBid]),
                client(Server, Topics, lists:filter(fun ({A, _, _}) ->
                    A /= Auction
                end, AuctionTopicBidTuples));
            lostAuction ->
                {Auction} = Details,
                io:fwrite("Client ~p lost Auction ~p~n", [Client, Auction]),
                client(Server, Topics, lists:filter(fun ({A, _, _}) ->
                    A /= Auction
                end, AuctionTopicBidTuples))
        end
    after
        1000 ->
            client(Server, Topics, AuctionTopicBidTuples)
    end.

% range(Lower, Upper) creates a list of integers
% ranging from Lower to Upper inclusive
range(N, N) ->
    [N];
range(Lower, Upper) ->
    [Lower|range(Lower + 1, Upper)].

timeInMs() ->
    round(erlang:system_time() / 1000000).

takeRandom(0, _) ->
    [];
takeRandom(_, []) ->
    [];
takeRandom(N, L) ->
    Index = rand:uniform(length(L)),
    [lists:nth(Index, L)|takeRandom(N - 1, lists:merge(lists:sublist(L, N - 1), lists:nthtail(Index, L)))].
