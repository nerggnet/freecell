%% Terminal primitives for the FreeCell TUI.
%%
%% Gleam has no terminal library, so raw keyboard input goes through here.
%% `shell:start_interactive({noshell, raw})` requires OTP 26 or later; in raw
%% mode the VM stops line-buffering and echoing, so keypresses reach us as
%% bytes the instant they happen.
-module(freecell_ffi).

-export([start_raw/0, read_byte/0, term_size/0, write/1,
         await_input/0, read_input/1, arguments/0, now_micros/0,
         read_file/1, write_file/2, stats_path/0, version/0]).

start_raw() ->
    case shell:start_interactive({noshell, raw}) of
        ok ->
            %% Read bytes, not codepoint lists, so escape sequences stay intact.
            _ = io:setopts(standard_io, [binary]),
            start_reader(),
            {ok, nil};
        {error, Reason} ->
            {error, atom_to_binary(Reason, utf8)}
    end.

read_byte() ->
    case io:get_chars(standard_io, <<>>, 1) of
        Bin when is_binary(Bin) -> {ok, Bin};
        List when is_list(List) -> {ok, list_to_binary(List)};
        _ -> {error, nil}
    end.

term_size() ->
    Cols = case io:columns() of {ok, C} -> C; _ -> 80 end,
    Rows = case io:rows() of {ok, R} -> R; _ -> 24 end,
    {Cols, Rows}.

write(Bin) ->
    ok = io:put_chars(standard_io, Bin),
    nil.

%% Keypresses are pumped into our mailbox by a dedicated process.
%%
%% io:get_chars/3 blocks with no timeout, which would leave no way to tell a
%% bare Escape from the start of an arrow key's escape sequence. Reading in a
%% separate process turns keypresses into messages, and a message can be waited
%% for with a timeout.
start_reader() ->
    Owner = self(),
    spawn(fun() -> reader(Owner) end),
    nil.

reader(Owner) ->
    case io:get_chars(standard_io, <<>>, 1) of
        Bin when is_binary(Bin), byte_size(Bin) > 0 ->
            Owner ! {freecell_key, binary:first(Bin)},
            reader(Owner);
        [Byte | _] when is_integer(Byte) ->
            Owner ! {freecell_key, Byte},
            reader(Owner);
        _ ->
            Owner ! freecell_input_closed
    end.

%% Block until a key arrives.
await_input() ->
    receive
        freecell_input_closed -> closed;
        {freecell_key, Byte} -> {byte, Byte}
    end.

%% Wait up to Timeout milliseconds for a key.
read_input(Timeout) ->
    receive
        freecell_input_closed -> closed;
        {freecell_key, Byte} -> {byte, Byte}
    after Timeout -> timeout
    end.

arguments() ->
    [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].

now_micros() ->
    erlang:system_time(microsecond).

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> {ok, Bin};
        {error, _} -> {error, nil}
    end.

write_file(Path, Data) ->
    _ = filelib:ensure_dir(Path),
    case file:write_file(Path, Data) of
        ok -> {ok, nil};
        {error, _} -> {error, nil}
    end.

%% Where the record of games played lives. Follows XDG when it is set, and
%% falls back to the conventional location under HOME when it is not.
stats_path() ->
    Base = case os:getenv("XDG_DATA_HOME") of
        Dir when is_list(Dir), Dir =/= "" -> Dir;
        _ -> filename:join(os:getenv("HOME", "."), ".local/share")
    end,
    unicode:characters_to_binary(filename:join([Base, "freecell", "stats"])).

%% Read from the generated .app file rather than kept in step by hand, so a
%% packaged executable reports the version it was actually built from.
version() ->
    _ = application:load(freecell),
    case application:get_key(freecell, vsn) of
        {ok, Vsn} -> unicode:characters_to_binary(Vsn);
        _ -> <<"unknown">>
    end.
