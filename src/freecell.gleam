//// The program: set the terminal up, run the loop, put it back.

import freecell/deck
import freecell/render
import freecell/rules
import freecell/solver
import freecell/stats.{type Stats}
import freecell/tui/ansi
import freecell/tui/app
import freecell/tui/term
import gleam/int
import gleam/io
import gleam/list
import gleam/string

pub fn main() -> Nil {
  let args = term.arguments()
  case
    list.contains(args, "--help") || list.contains(args, "-h"),
    list.contains(args, "--version") || list.contains(args, "-V")
  {
    True, _ -> io.println(usage())
    _, True -> io.println("freecell " <> term.version())
    _, _ ->
      case list.contains(args, "--stats") {
        True -> io.println(stats.summary(load_record()))
        False -> start(args)
      }
  }
}

fn start(args: List(String)) -> Nil {
  case term.enter_raw() {
    Error(reason) -> io.println(advice(reason))
    Ok(Nil) -> {
      term.write(ansi.enter_full_screen() <> ansi.hide_cursor())
      let seed = starting_seed(args)
      let finished =
        loop(
          nothing_drawn,
          app.new(
            starting_game(args, seed),
            seed,
            chosen_options(args),
            load_record(),
            term.now(),
            chosen_mode(args),
          ),
        )
      // Reached on quit and on stdin closing, so the terminal is always handed
      // back the way it was found.
      term.write(ansi.show_cursor() <> ansi.leave_full_screen())
      save_record(finished)
    }
  }
}

/// Runs until the player quits or stdin closes, and hands back the final
/// state so the record can be written after the screen is restored.
/// How long to wait before looking around of our own accord. Frequent enough
/// that a resize and the ticking clock feel immediate, and free when nothing
/// has changed, because an identical frame is not painted again.
const tick_ms = 250

/// What is currently on the screen, so a frame that would look the same is not
/// painted a second time.
type Shown {
  Shown(size: #(Int, Int), lines: List(String))
}

const nothing_drawn = Shown(size: #(0, 0), lines: [])

fn loop(shown: Shown, state: app.State) -> app.State {
  // The clock lives out here, so the game itself stays a pure function of what
  // it is told.
  let ticking = app.at(state, term.now())
  let #(columns, rows) = term.size()
  // Reserve the deepest board's worth of lines so the layout keeps still, but
  // never more than the terminal has, or a short one would lose its footer.
  let wanted =
    Shown(
      #(columns, rows),
      app.screen(ticking, int.min(render.board_height, rows)),
    )
  let shown = case wanted == shown {
    True -> shown
    False -> {
      paint(wanted)
      wanted
    }
  }

  case term.next_event(tick_ms) {
    // Nothing happened; go round again in case the terminal or the clock has
    // moved on underneath us.
    term.Tick -> loop(shown, ticking)
    term.Gone -> ticking
    term.Pressed(pressed) -> react(shown, ticking, app.KeyPress(pressed))
    term.Delivered(#(generation, outcome)) ->
      react(shown, ticking, app.Searched(generation, outcome))
  }
}

/// Read the clock when the event arrives rather than when the frame was drawn.
/// Waiting for a key can take as long as the player likes, and a keypress that
/// resets the clock has to reset it to now, not to whenever the board was last
/// painted.
fn react(shown: Shown, state: app.State, input: app.Input) -> app.State {
  advance(shown, app.at(state, term.now()), input)
}

fn advance(shown: Shown, state: app.State, input: app.Input) -> app.State {
  case app.update(state, input) {
    app.Quit(final) -> final
    app.Continue(next) -> loop(shown, next)
    // Searching can take seconds, so it happens on another process and comes
    // back as an event; the loop keeps taking keys meanwhile.
    app.Think(next, generation, mode, board, budget) -> {
      term.in_background(fn() {
        #(generation, solver.solve(mode, board, budget))
      })
      loop(shown, next)
    }
  }
}

fn load_record() -> Stats {
  case term.read_file(term.stats_path()) {
    Ok(text) -> stats.parse(text)
    // No file yet, or one we cannot read: start from nothing rather than
    // refusing to play.
    Error(Nil) -> stats.empty()
  }
}

fn save_record(state: app.State) -> Nil {
  case term.write_file(term.stats_path(), stats.to_text(app.record(state))) {
    Ok(Nil) -> Nil
    // Not being able to keep score is no reason to complain on the way out.
    Error(Nil) -> Nil
  }
}

/// Paint a frame, centred in whatever size the terminal now is.
///
/// The size is read fresh each time round the loop rather than watched for
/// with a signal handler, and the loop comes round on its own every tick, so a
/// resize is picked up whether or not anyone is pressing keys.
fn paint(frame: Shown) -> Nil {
  let #(columns, rows) = frame.size
  let lines = frame.lines
  let indent =
    string.repeat(" ", int.max({ columns - render.board_width } / 2, 0))
  let above = int.max({ rows - list.length(lines) } / 2, 0)

  let body =
    list.append(
      list.repeat("", above),
      list.map(lines, fn(line) { indent <> line }),
    )
    // Clearing each line as we go stops a shorter frame leaving debris.
    |> list.map(fn(line) { line <> ansi.clear_to_end_of_line() })
    |> string.join("\r\n")

  term.write(ansi.move_to_home() <> body <> ansi.clear_to_end_of_screen())
}

fn starting_seed(args: List(String)) -> Int {
  case flag_value(args, "--seed") {
    Ok(seed) -> seed
    Error(Nil) -> term.now()
  }
}

fn starting_game(args: List(String), seed: Int) -> Int {
  case flag_value(args, "--game") {
    Ok(number) -> number
    Error(Nil) -> {
      let #(number, _) = deck.next_game_number(seed)
      number
    }
  }
}

/// Relaxed play lifts the limit on how many cards move at once. It is offered
/// at launch, and `m` switches it during a game, so a new deal can be started
/// either way without leaving the program.
fn chosen_mode(args: List(String)) -> rules.Mode {
  case list.contains(args, "--relaxed") || list.contains(args, "--casual") {
    True -> rules.Relaxed
    False -> rules.Standard
  }
}

fn chosen_options(args: List(String)) -> render.Options {
  render.Options(
    colour: !list.contains(args, "--no-colour")
      && !list.contains(args, "--no-color"),
    suits: case list.contains(args, "--ascii") {
      True -> render.Letters
      False -> render.Symbols
    },
  )
}

fn flag_value(args: List(String), flag: String) -> Result(Int, Nil) {
  case args {
    [name, value, ..] if name == flag -> int.parse(value)
    [_, ..rest] -> flag_value(rest, flag)
    [] -> Error(Nil)
  }
}

fn usage() -> String {
  "freecell — a FreeCell game for the terminal

  freecell [options]

    --game N      deal Microsoft FreeCell game number N (1-32000)
    --seed N      fix the shuffle that `n` draws new games from
    --relaxed     lift the limit on how many cards move at once
                  (also --casual); m switches it during a game
    --ascii       write suits as C D H S instead of ♣ ♦ ♥ ♠
    --no-colour   no colour (also --no-color)
    --stats       print your record and exit
    --version     print the version
    --help        this message

  Press ? in the game for the keys."
}

fn advice(reason: String) -> String {
  case reason {
    "enotsup" ->
      "freecell needs a terminal. Run ./run.sh from a shell, not through a pipe."
    "already_started" ->
      "Something else already owns the keyboard. Run ./run.sh rather than gleam run."
    other -> "Could not set up the terminal: " <> other
  }
}
