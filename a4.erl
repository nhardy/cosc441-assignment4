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
            auction(Server, Topic, 0, rand:uniform(100))
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
    ok.

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
                            Auction ! {msg, interestedClient, {Client}}
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

auction(Server, Topic, Deadline, MinBid) ->
    auction(Server, Topic, Deadline, MinBid, []).

auction(Server, Topic, Deadline, MinBid, ClientBidPairs) ->
    Auction = self(),
    % TODO: Check whether deadline has elapsed and determine the winner
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
    end.

client(Server) ->
    Client = self(),
    AllTopics = topics(),
    Topics = takeRandom(rand:uniform(length(AllTopics)), AllTopics),
    Server ! {msg, subscribe, {Client, Topics}},
    client(Server, Topics, []).

client(Server, Topics, AuctionTopicBidTuples) ->
    Client = self(),
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
    end,
    ok.

% range(Lower, Upper) creates a list of integers
% ranging from Lower to Upper inclusive
range(N, N) ->
    [N];
range(Lower, Upper) ->
    [Lower|range(Lower + 1, Upper)].

takeRandom(0, _) ->
    [];
takeRandom(_, []) ->
    [];
takeRandom(N, L) ->
    Index = rand:uniform(length(L)),
    [lists:nth(Index, L)|takeRandom(N - 1, lists:merge(lists:sublist(L, N - 1), lists:nthtail(Index, L)))].
