#!/usr/bin/env escript
%%! -noshell
-include_lib("kernel/include/file.hrl").

%% Packages the game as one self-contained executable.
%%
%% The result is an escript: a zip archive of every compiled module with a
%% shebang and emulator flags on the front. It needs Erlang on the machine that
%% runs it, but not Gleam, and not this repository.
%%
%% +Bc is baked into the emulator arguments deliberately. Without it the BEAM's
%% break handler swallows Ctrl-C and paints its menu over the board — the same
%% reason run.sh sets ERL_FLAGS. The flag belongs in the executable rather than
%% in a wrapper script, so there is nothing for a packager to forget.
main([Shipment, Output]) ->
    Files = beam_files(Shipment),
    case Files of
        [] ->
            io:format(standard_error, "no compiled modules under ~s~n", [Shipment]),
            halt(1);
        _ ->
            {ok, {_Name, Archive}} =
                zip:create("freecell.zip", Files, [memory, {cwd, Shipment}]),
            ok = escript:create(Output, [
                shebang,
                {emu_args, "+Bc -escript main freecell_escript"},
                {archive, Archive}
            ]),
            ok = file:change_mode(Output, 8#755),
            {ok, #file_info{size = Size}} = file:read_file_info(Output),
            io:format("~s  (~p modules, ~p KB)~n",
                      [Output, length(Files), Size div 1024])
    end;
main(_) ->
    io:format(standard_error, "usage: package.escript <shipment-dir> <output>~n", []),
    halt(1).

%% Paths relative to the shipment directory, in the app/ebin layout the code
%% server expects to find inside an archive.
beam_files(Shipment) ->
    Prefix = Shipment ++ "/",
    [relative(Path, Prefix)
     || Path <- filelib:wildcard(filename:join([Shipment, "*", "ebin", "*"]))].

relative(Path, Prefix) ->
    case string:prefix(Path, Prefix) of
        nomatch -> Path;
        Rest -> Rest
    end.
