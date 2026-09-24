#!/bin/sh
# Launch the game.
#
# +Bc is required: without it the BEAM's break handler swallows Ctrl-C and
# paints its menu over the board. With it, Ctrl-C arrives as byte 3 and the
# game handles it like any other key.
#
# The -- separates our flags from gleam's, so ./run.sh --game 617 works.
exec env ERL_FLAGS="+Bc" gleam run -- "$@"
