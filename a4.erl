-module(a4).
-export([a4/0]).

% topics() returns a list of topic atoms
topics() ->
    [topic1, topic2, topic3, topic4, topic5].

% a4() initiates behaviour as described by assignment 4
a4() ->
    % Create a local copy of the list of all topics
    AllTopics = topics(),
    % Keep a reference to this process
    Self = self(),

    % Start the 'Server'
    spawn_link(fun() ->
        server(Self)
    end),

    % Wait until the Server has registered with the Erlang process registry
    receive {registered} ->
        % We will spawn a random number of Auctions between 1 and 5
        NumAuctions = rand:uniform(5),
        % Create a range from 1 to NumAuctions and map over this, creating a
        % list of {Auction, Topic} tuples
        AuctionTopicPairs = lists:map(fun (_) ->
            % Pick a topic at random
            Topic = lists:nth(rand:uniform(length(AllTopics) - 1), AllTopics),
            % Spawn an Auction with that Topic, keeping track of its process ID
            Auction = spawn_link(fun () ->
                auction(Topic)
            end),
            io:fwrite("Spawned Auction ~p with Topic: ~s~n", [Auction, Topic]),
            {Auction, Topic}
        end, range(1, NumAuctions)),

        % Inform the Server of the initial list of AuctionTopicPairs so that it
        % may enter the main loop and begin listening for other communications
        server ! {init, AuctionTopicPairs},

        % We will spawn a random number of Clients between 10 and 15
        NumClients = 9 + rand:uniform(6),
        % Create a range from 1 to NumClients and for each element, create a new
        % Client process, passing it the reference to the Server's process ID
        lists:foreach(fun (_) ->
            spawn_link(fun () ->
                client()
            end)
        end, range(1, NumClients)),

        % Simulate the random creation of new Auctions
        spawnThings()
    end.

% spawnThings() runs the spawnThings process 10 times
spawnThings() ->
    spawnThings(10).
% spawnThings(N) will randomly spawn new Auctions N times
spawnThings(0) ->
    ok;
spawnThings(N) ->
    % Sleep for a random number of seconds between 1 and 5
    timer:sleep(rand:uniform(5) * 1000),

    % We will spawn between 1 and 5 new Auctions
    NumAuctions = rand:uniform(5),
    % Create a range from 1 to NumAuctions and for each element, create a new
    % Auction process, passing in only a reference to the Server's process ID
    lists:foreach(fun (_) ->
        spawn_link(fun () ->
            auction()
        end)
    end, range(1, NumAuctions)),

    % We will spawn between 10 and 15 new Clients
    NumClients = rand:uniform(9 + rand:uniform(6)),
    % Create a range from 1 to NumClients and for each element, create a new
    % Client process, passing it the reference to the Server's process ID
    lists:foreach(fun (_) ->
        spawn_link(fun () ->
            client()
        end)
    end, range(1, NumClients)),

    % Recurse, reducing the counter for the number of times
    % the function must recurse further
    spawnThings(N - 1).

% Starts the Server logic by initially waiting to receive a list
% of AuctionTopicPairs before entering the main loop
server(Creator) ->
    % Register self as the server
    register(server, self()),
    % Tell the Creator of this process that the Server has been registered
    Creator ! {registered},
    % Receive initialisation data
    receive {init, AuctionTopicPairs} ->
        server(AuctionTopicPairs, [])
    end.

% Main server loop which continually calls itself after dealing with each message
server(AuctionTopicPairs, ClientTopicsPairs) ->
    % Messages are received in this form as a tuple where Details itself is a
    % tuple whose length and contents vary depending on the MsgType
    receive {msg, MsgType, Details} ->
        % Switch on the MsgType parameter
        case MsgType of
            % When we hear about a new Auction
            newAuction ->
                % Grab the details
                {Auction, Topic} = Details,

                % For each of our existing ClientTopicsPairs
                lists:foreach(fun ({Client, Topics}) ->
                    % Check whether the Client has the Auction's Topic in its list of Topics
                    IsClientMaybeInterested = lists:member(Topic, Topics),
                    if
                        % If it does, then it might be interested
                        IsClientMaybeInterested ->
                            % So tell that Auction about this potentially interested Client
                            Auction ! {msg, interestedClient, {Client}};

                        % Otherwise
                        true ->
                            % Do nothing
                            ok
                    end
                end, ClientTopicsPairs),

                % Add the {Auction, Topic} pair to this list by recursing
                server([{Auction, Topic}|AuctionTopicPairs], ClientTopicsPairs);

            % When we hear about a new Client subscribing
            subscribe ->
                % Grab the details
                {Client, Topics} = Details,

                % For each of our existing AuctionTopicPairs
                lists:foreach(fun ({Auction, Topic}) ->
                    % Check whether this Client has the Auction's Topic in its list of Topics
                    IsClientMaybeInterested = lists:member(Topic, Topics),
                    if
                        % If it does, then it might be interested
                        IsClientMaybeInterested ->
                            % So tell the Auction of this Client
                            Auction ! {msg, interestedClient, {Client}};

                        % Otherwise
                        true ->
                            % Do nothing
                            ok
                    end
                end, AuctionTopicPairs),

                % Add the {Client, Topics} pair to this list by recursing
                server(AuctionTopicPairs, [{Client, Topics}|ClientTopicsPairs]);

            % When we hear about a Client wishing to unsubscribe
            unsubscribe ->
                % Grab the Client's process ID
                {Client} = Details,

                % Remove the Client from the list of ClientTopicsPairs by recursing
                server(AuctionTopicPairs, lists:filter(fun ({C, _}) ->
                    % Keep Clients that are not the Client currently unsubscribing
                    C /= Client
                end, ClientTopicsPairs))
        end
    end.

% auction() will start the Auction logic by first choosing a random topic
% and then informing the Server before entering the next section of logic to
% generate a Deadline and MinBid
auction() ->
    % This Auction is the current process
    Auction = self(),
    % Create a local copy of the list of all topics
    AllTopics = topics(),
    % Pick a random Topic
    Topic = lists:nth(rand:uniform(length(AllTopics)), AllTopics),
    % Let the Server know about this new Auction including its Topic
    server ! {msg, newAuction, {Auction, Topic}},
    % Go to the next step
    auction(Topic).

% auction(Topic) will first generate a random deadline and a MinBid,
% before entering the main logic loop
auction(Topic) ->
    % Pick a random deadline between 1 second from now and 3 seconds from now
    Deadline = timeInMs() + 1000 + rand:uniform(2000),
    % Pick and random MinBid between 1 and 50
    MinBid = rand:uniform(50),
    % Start the main logic loop
    auction(Topic, Deadline, MinBid, []).

% auction(Topic, Deadline, MinBid, ClientBidPairs) is the main logic loop
% that continually calls itself while the Auction is in progress until its completion
auction(Topic, Deadline, MinBid, ClientBidPairs) ->
    % Keep a reference to this Auction's process
    Auction = self(),
    % Check if we're past the Auction deadline
    IsPastDeadline = timeInMs() >= Deadline,
    if
        % If we are past the deadline
        IsPastDeadline ->
            if
                % If there no Clients interested
                length(ClientBidPairs) == 0 ->
                    % Do nothing - this Auction ends
                    ok;

                % If there was only one interested Client
                length(ClientBidPairs) == 1 ->
                    % Grab the reference to the Winner's process ID
                    [{Winner, _}] = ClientBidPairs,
                    % Inform the Winner that they won and that there was no second highest bid
                    Winner ! {msg, wonAuction, {Auction, -1}},
                    % This Auction ends
                    ok;

                % Otherwise
                true ->
                    % Grab the reference to the Winner's process ID, and the NextHighestBid after
                    % sorting the list of ClientBidPairs by the bid amount, discarding all others
                    [{Winner, _}|[{_, NextHighestBid}|_]] = lists:sort(fun ({_, B1}, {_, B2}) ->
                        B1 =< B2
                    end, ClientBidPairs),

                    % For each of the Clients that were still interested
                    lists:foreach(fun ({Client, _}) ->
                        if
                            % If this Client won
                            Client == Winner ->
                                % Let the Client know that they won this Auction and what the
                                % NextHighestBid was, or if there wasn't another bid, -1
                                Client ! {msg, wonAuction, {Auction, NextHighestBid}};

                            % Otherwise
                            true ->
                                % Let the Client know that they lost this Auction
                                Client ! {msg, lostAuction, {Auction}}
                        end
                    end, ClientBidPairs),
                    % This Auction ends
                    ok
            end;

        % Otherwise
        true ->
            % Messages are received in this form as a tuple where Details itself is a
            % tuple whose length and contents vary depending on the MsgType
            receive {msg, MsgType, Details} ->
                % Switch on the MsgType parameter
                case MsgType of
                    % When we have a new interested Client
                    interestedClient ->
                        % Grab the Client's process ID
                        {Client} = Details,

                        % Calculate the CurrentMinBid by folding over the list of
                        % ClientBidPairs and finding the maximum of all (Bids + 1)
                        % and the starting MinBid
                        CurrentMinBid = lists:foldl(fun ({_, Bid}, Acc) ->
                            max(Acc, Bid + 1)
                        end, MinBid, ClientBidPairs),

                        % Tell the potentially interested Client about this Auction,
                        % what its Topic is, and the CurrentMinBid
                        Client ! {msg, auctionAvailable, {Auction, Topic, CurrentMinBid}},

                        % Add this Client with a non-bid (-1) to our list of ClientBidPairs by recursing
                        auction(Topic, Deadline, MinBid, [{Client, -1}|ClientBidPairs]);

                    % When we receive a new bid
                    bid ->
                        % Grab the Client's process ID and the Bid amount from the details
                        {Client, Bid} = Details,

                        % Calculate the CurrentMinBid by folding over the list of
                        % ClientBidPairs and finding the maximum of all (Bids + 1)
                        % and the starting MinBid
                        CurrentMinBid = lists:foldl(fun ({_, B}, Acc) ->
                            max(Acc, B + 1)
                        end, MinBid, ClientBidPairs),

                        if
                            % If the incoming Bid is greater than or equal to the CurrentMinBid
                            Bid >= CurrentMinBid ->
                                io:fwrite("Auction ~p received bid from Client ~p: ~B~n", [Auction, Client, Bid]),

                                % The Bid was successful, so for each Client
                                lists:foreach(fun ({C, _}) ->
                                    % Tell them what the new Bid is
                                    C ! {msg, newBid, {Auction, Bid}}
                                end, ClientBidPairs),

                                % Recurse into the loop again, replacing the Client's current Bid with the new one
                                auction(Topic, Deadline, MinBid, lists:map(fun ({C, B}) ->
                                    if
                                        % If this element is for the current Client
                                        C == Client ->
                                            % Replace its previous Bid with the new Bid
                                            {C, Bid};

                                        % Otherwise
                                        true ->
                                            % Leave it as-is
                                            {C, B}
                                    end
                                end, ClientBidPairs));

                            % Otherwise
                            true ->
                                % The Bid doesn't count, so just loop
                                auction(Topic, Deadline, MinBid, ClientBidPairs)
                        end;

                    % When a Client is no-longer interested
                    notInterested ->
                        % Grab the Client's process ID
                        {Client} = Details,
                        % Recurse, filtering the Client's entry from the list of ClientBidPairs
                        auction(Topic, Deadline, MinBid, lists:filter(fun({C, _}) ->
                            % Keep the ClientBidPair if this Client is not the Client
                            % that is telling us it is no longer interested
                            C /= Client
                        end, ClientBidPairs))
                end
            after
                % If we don't receive any new messages, we still want to check whether the deadline
                % has passed yet or not, so after 1 second with no messages, recurse
                1000 ->
                    auction(Topic, Deadline, MinBid, ClientBidPairs)
            end
    end.

% client() creates a new Client logic loop
client() ->
    % Keep a reference to the current process
    Client = self(),
    % Create a local copy of the list of all topics
    AllTopics = topics(),
    % Pick a random selection of Topics
    Topics = takeRandom(rand:uniform(length(AllTopics)), AllTopics),
    % Let the Server know about this Client and which Topics it is interested in
    server ! {msg, subscribe, {Client, Topics}},
    % Start the main loop
    client(Topics, []).

% client(Topics, AuctionTopicBidTuples) is the main logic loop for the Client process
client(Topics, AuctionTopicBidTuples) ->
    % Keep a reference to the Client's process
    Client = self(),

    % TODO: simulate random loss of interest in Topics

    % Messages are received in this form as a tuple where Details itself is a
    % tuple whose length and contents vary depending on the MsgType
    receive {msg, MsgType, Details} ->
    % Switch on the MsgType parameter
        case MsgType of
            % When we are informed of a new Auction
            auctionAvailable ->
                % Grab the Details
                {Auction, Topic, MinBid} = Details,

                % If it's a Topic in our list, then there is a 67% chance that we are interested
                IsInterested = lists:member(Topic, Topics) and (rand:uniform(100) =< 67),
                if
                    % If we are interested
                    IsInterested ->
                        % Choose a random amount to bid at or above the current MinBid by up to 5
                        Bid = MinBid + rand:uniform(5) - 1,
                        % Make that Bid
                        Auction ! {msg, bid, {Client, Bid}},
                        % Recurse, adding this Auction, its Topic and our Bid to the list of AuctionTopicBidTuples
                        client(Topics, [{Auction, Topic, Bid}|AuctionTopicBidTuples]);

                    % Otherwise
                    true ->
                        % Tell the Auction that we are not interested
                        Auction ! {msg, notInterested, {Client}},
                        % Recurse, without adding the Auction to the list of AuctionTopicBidTuples
                        client(Topics, AuctionTopicBidTuples)
                end;

            % When we hear about a new bid
            newBid ->
                % Grab the details
                {Auction, CurrentBid} = Details,
                % Check if we are still interested, or had unsubscribed
                WasInterested = lists:member(Auction, lists:map(fun ({A, _, _}) ->
                    A
                end, AuctionTopicBidTuples)),
                if
                    % If we were still interested
                    WasInterested ->
                        % Get our current bid for this Auction, or -1 if we have not bid
                        OurBid = lists:foldl(fun ({_, _, B}, _) ->
                            B
                        end, -1, lists:filter(fun ({A, _, _}) ->
                            A == Auction
                        end, AuctionTopicBidTuples)),
                        % If we're the current highest bidder, or a 99% chance, we want to stay in the Auction
                        IsStillInterested = (OurBid == CurrentBid) or (rand:uniform(100) =< 99),
                        if
                            % If we are still interested
                            IsStillInterested ->
                                % Check if we should bid (if OurBid is not already the CurrentBid AND a 50% chance)
                                ShouldBid = (OurBid /= CurrentBid) and (rand:uniform(100) =< 50),
                                if
                                    % If we should bid
                                    ShouldBid ->
                                        % NewBid will be the CurrentBid plus a random numner, 1 to 5
                                        NewBid = CurrentBid + rand:uniform(5),
                                        % Inform the Auction of the NewBid
                                        Auction ! {msg, bid, {Client, NewBid}},

                                        % Update the list of AuctionTopicBidTuples, setting the relevant tuples Bid to the NewBid
                                        client(Topics, lists:map(fun ({A, T, B}) ->
                                            if
                                                % If the Auction in the list is the current Auction
                                                A == Auction ->
                                                    % Update the Bid
                                                    {A, T, NewBid};

                                                % Otherwise
                                                true ->
                                                    % Leave the tuple as-is
                                                    {A, T, B}
                                            end
                                        end, AuctionTopicBidTuples));

                                    % Otherwise
                                    true ->
                                        % We're not bidding, so just loop around
                                        client(Topics, AuctionTopicBidTuples)
                                end;

                            % Otherwise
                            true ->
                                % Let the Auction know we're no longer interested
                                Auction ! {msg, notInterested, {Client}},

                                % Remove the Auction from our list of AuctionTopicBidTuples
                                client(Topics, lists:filter(fun ({A, _, _}) ->
                                    % Keep the tuple if it is not the Auction we're looking for
                                    A /= Auction
                                end, AuctionTopicBidTuples))
                        end;

                    % Otherwise
                    true ->
                        % We've unsubscribed already, but the Auction probably hasn't processed that yet
                        % so we can just ignore this message and continue looping
                        client(Topics, AuctionTopicBidTuples)
                end;

            % When we've won an Auction
            wonAuction ->
                % Grab the Details
                {Auction, NextHighestBid} = Details,
                io:fwrite("Client ~p won Auction ~p where the next highest bid was ~B~n", [Client, Auction, NextHighestBid]),
                % Remove that Auction from our list
                client(Topics, lists:filter(fun ({A, _, _}) ->
                    % Keep the tuple if it is not the Auction we're looking for
                    A /= Auction
                end, AuctionTopicBidTuples));

            % When we've lost an Auction
            lostAuction ->
                % Grab the details
                {Auction} = Details,
                io:fwrite("Client ~p lost Auction ~p~n", [Client, Auction]),
                % Remove that Auction from our list
                client(Topics, lists:filter(fun ({A, _, _}) ->
                    % Keep the tuple if it is not the Auction we're looking for
                    A /= Auction
                end, AuctionTopicBidTuples))
        end
    after
        % If we don't receive any new messages, we still want to simulate the random
        % loss of interest in Topics, so after 1 second with no messages, recurse
        1000 ->
            client(Topics, AuctionTopicBidTuples)
    end.

% range(Lower, Upper) creates a list of integers ranging from Lower to Upper inclusive
range(N, N) ->
    [N];
range(Lower, Upper) ->
    [Lower|range(Lower + 1, Upper)].

% timeInMs() gets the system time in milliseconds
timeInMs() ->
    round(erlang:system_time() / 1000000).

% takeRandom(N, L) will try to pick N random elements from L
takeRandom(0, _) ->
    % When we've reached the number of required elements, don't add more
    [];
takeRandom(_, []) ->
    % When there are no more elements, just return an empty list
    [];
takeRandom(N, L) ->
    % Pick a random element from the list
    Index = rand:uniform(length(L)),
    % Return that element, plus this function called again with N-1 and the remaining elements in the list
    [lists:nth(Index, L)|takeRandom(N - 1, lists:merge(lists:sublist(L, N - 1), lists:nthtail(Index, L)))].
