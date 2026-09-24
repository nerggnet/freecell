# freecell

FreeCell for the terminal, written in Gleam and running on the BEAM.

```
  FreeCell #617                                 moves 24

   a    s    d    f                  ♣    ♦    ♥    ♠
  [5♥] [  ] [  ] [K♣]               [A♣] [3♦] [  ] [2♠]

   1      2      3      4      5      6      7      8
   7♦     A♦     5♣     3♠     5♠     8♣     2♦     A♥
   T♦     7♠     Q♦     A♣     6♦     8♥     A♠     K♥
   T♥     Q♣     3♥     9♦     6♠     8♦     3♦     T♣
   K♦     5♥     9♠     3♣     8♠     7♥     4♦    >J♠<
   4♣

  1-8 col · asdf cells · space home · u undo · q quit
```

## Installing

Download `freecell` from the [latest
release](https://github.com/nerggnet/freecell/releases/latest):

```sh
curl -LO https://github.com/nerggnet/freecell/releases/latest/download/freecell
chmod +x freecell
./freecell
```

One file, no installer. It needs Erlang/OTP 26 or later on the machine that
runs it, but not Gleam and not this repository.

## Playing

```sh
./freecell              # a game at random
./freecell --game 617   # a particular deal
./freecell --help       # all the options
```

Moves take two keys: one to pick a card up, one to say where it goes.

| key | |
|---|---|
| `1`–`8` | pick up a column |
| `a s d f` | pick up a free cell |
| `space` | send the card in hand to its foundation |
| `esc` | put the card back |
| `u` / `r` | undo / redo |
| `n` | deal a new game |
| `h` | suggest a move, if there is one |
| `!` | finish the game, if it can be finished |
| `p` | auto-play to the foundations on/off |
| `?` | the key list, and your record |
| `q` | quit |

Picking up a column takes the whole run at its foot, not just the bottom card,
and moves as many of them as there is room for. Cards that can no longer be
needed are sent to the foundations automatically; `p` turns that off.

Games are numbered as in Microsoft FreeCell, so `--game 617` deals the same
cards here as anywhere else. Wins and losses are kept in
`$XDG_DATA_HOME/freecell/stats`, or `~/.local/share/freecell/stats`.

## How it is put together

The rules are a pure core with the terminal pushed to the edges. Nothing in
`board`, `rules`, `game` or `render` performs I/O, which is why almost all of
it can be tested without a terminal anywhere in sight.

| | |
|---|---|
| `card`, `deck` | cards, and the deal algorithm behind the numbered games |
| `board` | eight cascades, four free cells, four foundations |
| `rules` | what is legal, runs of cards, auto-play, won and stuck |
| `solver` | a best-first search, behind hints and finishing |
| `game` | a game in progress, with undo and redo |
| `render` | a board to lines of text — optionally coloured |
| `stats` | the record, and its file format |
| `tui/key`, `tui/app` | keys, and what each one does — still pure |
| `tui/term`, `tui/ansi`, `freecell_ffi.erl` | the only parts that touch the terminal |
| `freecell` | set the terminal up, run the loop, put it back |
| `freecell_escript.erl` | entry point for the packaged executable |

Gleam has no terminal library, so raw keyboard input goes through a small
Erlang module. Keypresses are read by a dedicated process and delivered as
messages, which is what makes it possible to tell a bare `esc` from the start
of an arrow key's escape sequence.

**`run.sh` exists for a reason.** It sets `ERL_FLAGS=+Bc`; without it the
BEAM's break handler swallows Ctrl-C and paints its menu over the board. The
packaged executable bakes the same flag into its emulator arguments, so there
is nothing for a packager to forget — note that the `entrypoint.sh` which
`gleam export erlang-shipment` generates does *not* set it, and has the bug.

## Development

```sh
./run.sh --game 1        # play without packaging
gleam test               # the lot, in about a second
gleam format src test
./package.sh             # build build/freecell
```

`package.sh` exports an Erlang shipment and wraps every compiled module into a
single escript. Pushing a `v*` tag builds and publishes one the same way, from
`.github/workflows/release.yml`.

`src/freecell/solver.gleam` is a best-first search. It powers `h` and `!`, and
it underwrites the tests: the rules are checked against whether real numbered
deals can actually be played through to a win. It solves most deals in well
under 100ms, though a few — game 617 among them — defeat it, which is why a
hint is allowed to say it cannot find one.

Searching runs on its own process and its result arrives as one more event the
loop already waits for, so the game keeps taking keys while it thinks.
