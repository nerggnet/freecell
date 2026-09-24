%% Entry point for the packaged single-file escript.
%%
%% escript calls main/1, while Gleam generates main/0, so this bridges the two.
%% Arguments are not passed through: they are read from
%% init:get_plain_arguments/0, which holds them under both escript and
%% `gleam run`.
-module(freecell_escript).

-export([main/1]).

main(_Args) ->
    freecell:main().
