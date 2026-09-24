//// The program: set the terminal up, run the loop, put it back.

import freecell/deck
import freecell/render
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
    _, _ -> start(args)
  }
}

fn start(args: List(String)) -> Nil {
  case term.enter_raw() {
    Error(reason) -> io.println(advice(reason))
    Ok(Nil) -> {
      term.write(ansi.enter_full_screen() <> ansi.hide_cursor())
      let seed = starting_seed(args)
      let finished =
        loop(app.new(
          starting_game(args, seed),
          seed,
          chosen_options(args),
          load_record(),
        ))
      // Reached on quit and on stdin closing, so the terminal is always handed
      // back the way it was found.
      term.write(ansi.show_cursor() <> ansi.leave_full_screen())
      save_record(finished)
    }
  }
}

/// Runs until the player quits or stdin closes, and hands back the final
/// state so the record can be written after the screen is restored.
fn loop(state: app.State) -> app.State {
  draw(state)
  case term.read_key() {
    Error(Nil) -> state
    Ok(pressed) ->
      case app.update(state, pressed) {
        app.Quit(final) -> final
        app.Continue(next) -> loop(next)
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

/// Paint a frame, centred in whatever the terminal is now.
///
/// The size is read fresh every time rather than watched for, so a resize
/// takes effect on the next keypress.
fn draw(state: app.State) -> Nil {
  let #(columns, rows) = term.size()
  let lines = app.screen(state)
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
    --ascii       write suits as C D H S instead of ♣ ♦ ♥ ♠
    --no-colour   no colour (also --no-color)
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
