# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
./run.sh --game 1        # play a known deal — NOT `gleam run`, see below
gleam test               # every test, about a second
gleam format src test    # CI runs `gleam format --check src test` and fails on drift
./package.sh             # build build/freecell, the single-file executable
```

**Play with `./run.sh`, never bare `gleam run`.** It sets `ERL_FLAGS=+Bc`.
Without that flag the BEAM's break handler swallows Ctrl-C and paints its menu
over the board. `+Bd` is worse: it kills the VM and leaves the terminal in raw
mode with echo off. The packaged executable bakes `+Bc` into its own emulator
arguments; the `entrypoint.sh` that `gleam export erlang-shipment` generates
does **not**, and has the bug.

**Running one test.** gleeunit has no filter — it runs every `*_test` function
under `test/`. After `gleam test` has compiled, single tests can be run
directly:

```sh
erl -pa build/dev/erlang/*/ebin -noshell -eval 'eunit:test(card_test, [verbose]), halt().'
erl -pa build/dev/erlang/*/ebin -noshell -eval 'eunit:test({card_test, colors_test}, [verbose]), halt().'
```

## Architecture

The rules are a pure core with the terminal pushed to the edges. Nothing in
`card`, `deck`, `board`, `location`, `rules`, `game`, `render`, `stats`,
`tui/key` or `tui/app` performs I/O. Only `tui/term`, `tui/ansi`,
`freecell_ffi.erl` and `freecell.gleam` do. That boundary is why almost the
whole game is tested without a terminal, and it is worth defending.

**`board` is opaque and changes only through `take`/`place`**, a pair that
moves exactly one card. It cannot reach a state with 51 or 53 cards; a test
asserts that across every legal move on a real deal. Runs of several cards are
built on those primitives — lifted one at a time and laid back down deepest
first — rather than a separate bulk path.

**Cascades are stored exposed-card-first**, the reverse of how they print and
of what `deck.deal` returns. That makes every move a head pattern match.
`board.new` does the single reversal and `cascade_display` undoes it for the
renderer; those are the only two places the orderings meet.

**`rules.legal` is defined as "`rules.apply` succeeds"**, so there is no second
copy of the rules to drift out of step.

**`tui/app.update` is pure and must stay that way.** It never searches and
never reads the clock. To search it returns `Think(...)`, saying what wants
searching, and the loop in `freecell.gleam` does the blocking part. The clock
is handed in by `app.at` before each event. Both are deliberate: they are what
make key handling testable without a terminal.

**One receive handles everything.** Keypresses arrive as messages from a
dedicated reader process, search results from a spawned search, and a deadline
produces a tick. `term.next_event` folds all three into one type. The reader
process exists because `io:get_chars/3` blocks with no timeout, which would
leave no way to tell a bare Escape from the start of an arrow key's escape
sequence.

**Stale searches** are dropped by a generation counter bumped whenever the
board changes, so an answer about a position that no longer exists is
recognised rather than acted on.

**Idle redraw**: the loop comes round every 250ms and re-renders. A frame
identical to what is already on screen is not painted again, so idling costs
nothing while a resize and the ticking clock are still noticed.

## Rendering

Every slot is exactly `slot_width` columns. **Colour is applied inside that
width and never padded around**, because an escape sequence has length but no
width — and `A♠` is two columns but four bytes. Measure with `string.length`
(grapheme-aware), never byte size.

`render.frame` produces `14 + tallest cascade` lines. A cascade can never
exceed 19 cards (a dealt seven ending in a king, plus a full queen-to-ace run),
so the worst board is 33 rows and 64 columns. A test pins this.

`test/render_test.gleam` holds a **golden fixture** — the whole screen for game
1, exactly. Regenerate rather than transcribe it, via an escript against
`build/dev/erlang/*/ebin` calling `freecell@render:frame/2`. A layout change
must be looked at and accepted deliberately.

`--ascii` swaps both the suit symbols and the box-drawing characters; changing
one without the other leaves half the board undrawable on plain terminals.

## The solver

`src/freecell/solver.gleam` is a best-first search behind `h` and `!`, and it
underwrites the tests: the rules are checked by whether real numbered deals can
be played through to a win. It solves most deals in under 100 ms but **fails on
deals 617 and 4** — 617 resisted a 250,000-position budget. The replay tests
use deals 1, 3, 7, 8, 14 and 15 for that reason; do not "fix" them by switching
to 617.

Search exhaustion is **not** proof of unsolvability: `candidates` prunes moves
that are only mostly redundant. Deal 11982 (the known-unsolvable one) exhausts,
but that is evidence, not a proof.

## Testing a terminal

Raw mode needs a real tty, so manual checks run under
`script -q /dev/null <wrapper>`. Keystrokes must be **delayed** until raw mode
is live, e.g. `perl -e '$|=1; sleep 5; print "\003"'` — bytes sent earlier are
eaten by the pty's line discipline and produce misleading results. Several real
bugs here were invisible to unit tests and only showed up this way.

gleeunit scales eunit's timeouts by ten, so a test has roughly 50 seconds. Keep
solver budgets well inside that.

## Gleam notes for this project

- `gleam_stdlib` here has no `list.range`. It is `int.range`, and it is a
  **fold with an exclusive upper bound**, not a list constructor.
- `auto` is a reserved word; the field is `autoplay`.
- A qualified call resolves to the module even when a parameter shadows its
  name, so `board.take(board, ...)` compiles. It reads badly; prefer not to
  rely on it in new code.
