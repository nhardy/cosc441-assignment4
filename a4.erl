-module(a4).
-export([a4/0]).

topics() ->
    [topic1, topic2, topic3, topic4, topic5].

a4() ->
    Topics = topics(),
    Server = self(),

    NumAuctions = rand:uniform(5),

     AuctionTopicPairs = lists:map(fun (_) ->
        Topic = lists:nth(rand:uniform(length(Topics) - 1), Topics),
        io:fwrite("Spawning Auction with Topic: ~s~n", [Topic]),
        {spawn_link(fun () ->
            auction(Server, Topic, 0, rand:uniform(100))
        end), Topic}
    end, range(1, NumAuctions)),

    NumClients = 9 + rand:uniform(6),
    lists:foreach(fun (_) ->
        spawn_link(fun () ->
            client(Server)
        end)
    end, range(1, NumClients)),
    ok.

auction(Server, Topic, Deadline, MinBid) ->
    ok.

client(Server) ->
    AllTopics = topics(),
    Topics = takeRandom(rand:uniform(length(AllTopics)), AllTopics),
    lists:foreach(fun (Topic) ->
        io:fwrite("client ~p has topic: ~s ~n", [self(), Topic])
    end, Topics),
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
