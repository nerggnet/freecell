# Contributing

Thanks for looking. This is a small game, and small contributions are welcome.

## Getting set up

You need [Gleam](https://gleam.run) and Erlang/OTP 26 or later.

```sh
gleam test               # everything, about a second
./run.sh --game 1        # play a known deal
```

Play with `./run.sh`, not bare `gleam run`. It sets `ERL_FLAGS=+Bc`; without
that flag the BEAM's break handler swallows Ctrl-C and paints its menu over the
board.

## Before you open a pull request

```sh
gleam test
gleam format src test
```

CI runs both, and the format check fails on any drift.

## What the code expects of you

**Keep the core pure.** The rules, the board, the renderer and the key handling
perform no I/O; only `tui/term`, `tui/ansi`, `freecell_ffi.erl` and
`freecell.gleam` do. That boundary is why nearly the whole game can be tested
without a terminal. If a change seems to need I/O further in, there is usually
a way to hand the result in instead — `app.at` does that for the clock, and
`app.update` returns a request to search rather than searching.

**Tests are part of the change.** New rules want a case in the table in
`test/rules_test.gleam`; new keys want one in `test/app_test.gleam`. If you
change the layout, regenerate the golden fixture in `test/render_test.gleam`
rather than editing it by hand, and look at the diff before accepting it.

**Anything touching the terminal needs to be run.** Several real bugs here —
Ctrl-C handling, a clock that reset to the wrong value — were invisible to the
unit tests and only appeared when the game was actually played. Say in your
pull request what you ran and what you saw.

`CLAUDE.md` describes the architecture and the traps in more detail. It is
written for an AI assistant but it is accurate, and it is the fastest way to
get your bearings.

## Reporting a bug

Include the version (`freecell --version`), the deal number from the header,
and what you pressed. Numbered deals are reproducible, so a deal number and a
key sequence is usually enough to see it happen.

## Licence

By contributing you agree that your work is licensed under the MIT Licence, as
the rest of the project is.
