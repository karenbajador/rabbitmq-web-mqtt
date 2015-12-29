%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2015 GoPivotal, Inc.  All rights reserved.
%%

-module(rabbit_web_mqtt_app).

-behaviour(application).
-export([start/2, stop/1]).

%% Dummy supervisor - see Ulf Wiger's comment at
%% http://erlang.2086793.n4.nabble.com/initializing-library-applications-without-processes-td2094473.html
-behaviour(supervisor).
-export([init/1]).

%%----------------------------------------------------------------------------

-spec start(_, _) -> {ok, pid()}.
start(_Type, _StartArgs) ->
    mqtt_init(),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec stop(_) -> ok.
stop(_State) ->
    ok.

init([]) -> {ok, {{one_for_one, 1, 5}, []}}.

%%----------------------------------------------------------------------------

mqtt_init() ->
    NbAcceptors = get_env(nb_acceptors, 1),
    CowboyOpts = get_env(cowboy_opts, []),

    Routes = cowboy_router:compile([{'_', [
        {"/example", cowboy_static, {priv_file, rabbitmq_web_mqtt, "example/index.html"}},
        {"/example/[...]", cowboy_static, {priv_dir, rabbitmq_web_mqtt, "example/"}},
        {"/ws", rabbit_web_mqtt_handler, []}
    ]}]),

    TCPConf0 = get_env(tcp_config, []),
    TCPConf = case proplists:get_value(port, TCPConf0) of
        undefined -> [{port, 15675}|TCPConf0];
        _ -> TCPConf0
    end,
    TCPPort = proplists:get_value(port, TCPConf),

    {ok, _} = cowboy:start_http(web_mqtt, NbAcceptors, TCPConf,
                                [{env, [{dispatch, Routes}]}|CowboyOpts]),

    rabbit_log:info("rabbit_web_mqtt: listening for HTTP connections on ~s:~w~n",
                    ["0.0.0.0", TCPPort]),

    case get_env(ssl_config, []) of
        [] ->
            ok;
        SSLConf ->
            rabbit_networking:ensure_ssl(),
            SSLPort = proplists:get_value(port, SSLConf),

            {ok, _} = cowboy:start_https(web_mqtt_secure, NbAcceptors, SSLPort,
                                         [{env, [{dispatch, Routes}]}|CowboyOpts]),
            rabbit_log:info("rabbit_web_mqtt: listening for HTTPS connections on ~s:~w~n",
                            ["0.0.0.0", SSLPort])
    end,
    ok.

get_env(Key, Default) ->
    case application:get_env(rabbitmq_web_mqtt, Key) of
        undefined -> Default;
        {ok, V}   -> V
    end.