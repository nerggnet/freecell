//// What each keypress does.
////
//// Pure. The loop that reads keys and paints the screen lives in `freecell`;
//// everything here is a plain function from state and key to new state, which
//// is what makes the interface testable without a terminal.

import freecell/board.{type Board}
import freecell/deck
import freecell/game.{type Game}
import freecell/location.{type Location, Cascade, Foundation, Free}
import freecell/render.{type Options, type View, View}
import freecell/rules.{type Illegal, type Move, Move}
import freecell/solver
import freecell/stats.{type Stats}
import freecell/tui/key.{type Key, Backspace, Char, Ctrl, Enter, Escape, Space}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Mode {
  Playing
  ConfirmQuit
  Help
}

pub opaque type State {
  State(
    game: Game,
    selection: Option(Location),
    message: String,
    mode: Mode,
    seed: Int,
    options: Options,
    record: Stats,
    thinking: Option(Wanted),
    /// Bumped whenever the board changes, so an answer about a board that no
    /// longer exists can be recognised and dropped.
    generation: Int,
    // Whether this game has already been added to the record, so that undoing
    // and re-winning, or quitting after a win, cannot count it twice.
    counted: Bool,
  )
}

pub type Step {
  Continue(state: State)
  /// Search this board and feed the outcome back in as `Searched`. Keeping the
  /// request in the return value is what lets `update` stay pure: it says what
  /// wants doing, and the loop does it somewhere that can afford to block.
  Think(state: State, generation: Int, board: Board, budget: Int)
  /// Carries the state so the caller can save the record before exiting.
  Quit(state: State)
}

/// Something for the game to react to.
pub type Input {
  KeyPress(key: Key)
  Searched(generation: Int, outcome: solver.Outcome)
}

/// What a search was asked for.
type Wanted {
  AHint
  AFinish
}

/// Positions to look at before giving up. The search runs elsewhere, so this
/// can be generous without the game becoming unresponsive.
const search_budget = 20_000

pub fn new(number: Int, seed: Int, options: Options, record: Stats) -> State {
  State(
    game: game.new(number),
    selection: None,
    message: "Pick a column with 1-8, or ? for the keys.",
    mode: Playing,
    seed:,
    options:,
    record:,
    counted: False,
    thinking: None,
    generation: 0,
  )
}

pub fn record(state: State) -> Stats {
  state.record
}

/// The lines to draw: the board, or the help screen over it.
pub fn screen(state: State) -> List(String) {
  case state.mode {
    Help -> render.help(state.record, state.options)
    _ -> render.frame(view(state), state.options)
  }
}

pub fn options(state: State) -> Options {
  state.options
}

pub fn game_number(state: State) -> Int {
  game.number(state.game)
}

pub fn view(state: State) -> View {
  let base =
    View(
      board: game.board(state.game),
      number: game.number(state.game),
      moves: game.moves(state.game),
      selection: state.selection,
      message: state.message,
    )
  case state.mode {
    ConfirmQuit ->
      View(..base, message: "Quit? y to quit, anything else to stay.")
    _ -> base
  }
}

pub fn update(state: State, input: Input) -> Step {
  case input {
    Searched(generation, outcome) -> searched(state, generation, outcome)
    KeyPress(pressed) -> pressed_key(state, pressed)
  }
}

fn pressed_key(state: State, pressed: Key) -> Step {
  case state.mode {
    // Any key dismisses the help, so nobody has to guess how to leave it.
    Help -> Continue(State(..state, mode: Playing))
    ConfirmQuit -> answer_quit(state, pressed)
    Playing -> play(state, pressed)
  }
}

fn answer_quit(state: State, pressed: Key) -> Step {
  case pressed {
    Char("y") | Char("Y") -> Quit(give_up(state))
    _ -> Continue(State(..state, mode: Playing, message: ""))
  }
}

fn play(state: State, pressed: Key) -> Step {
  case pressed {
    // Ctrl-C is the one key that does not stop to ask.
    Ctrl("c") -> Quit(give_up(state))
    Char("q") -> Continue(State(..state, mode: ConfirmQuit))
    Char("?") -> Continue(State(..state, mode: Help))
    Char("p") -> Continue(toggle_auto_play(state))
    Char("h") -> think(state, AHint)
    Char("!") -> think(state, AFinish)
    Char("u") -> Continue(undo(state))
    Char("r") -> Continue(redo(state))
    Char("n") -> Continue(deal_next(state))
    Escape | Backspace -> Continue(State(..state, selection: None, message: ""))
    Space | Enter -> Continue(send_home(state))
    Char(character) ->
      case place_for(character) {
        Ok(target) -> Continue(choose(state, target))
        Error(Nil) -> Continue(state)
      }
    _ -> Continue(state)
  }
}

/// The first press picks a card up, the second puts it down. Pressing the same
/// place twice puts it back.
fn choose(state: State, target: Location) -> State {
  case state.selection {
    None ->
      case board.exposed(game.board(state.game), target) {
        Ok(_) -> State(..state, selection: Some(target), message: "")
        Error(Nil) -> State(..state, message: "Nothing to pick up there.")
      }
    Some(source) if source == target ->
      State(..state, selection: None, message: "Put back.")
    Some(source) -> attempt(state, source, target)
  }
}

fn send_home(state: State) -> State {
  case state.selection {
    None -> State(..state, message: "Pick a card up first.")
    Some(source) ->
      case board.exposed(game.board(state.game), source) {
        Error(Nil) -> State(..state, selection: None, message: "")
        Ok(moving) -> attempt(state, source, Foundation(moving.suit))
      }
  }
}

fn attempt(state: State, source: Location, target: Location) -> State {
  case game.play(state.game, Move(source, target)) {
    Ok(#(next, carried)) ->
      note_win(changed(
        State(
          ..state,
          game: next,
          selection: None,
          message: carried_text(carried),
        ),
      ))
    // The selection stays put, so the player can simply aim somewhere else.
    Error(reason) -> State(..state, message: describe(reason))
  }
}

fn carried_text(carried: Int) -> String {
  case carried {
    1 -> ""
    many -> "Moved " <> int.to_string(many) <> " cards."
  }
}

fn undo(state: State) -> State {
  case game.undo(state.game) {
    Ok(previous) ->
      changed(
        State(..state, game: previous, selection: None, message: "Undone."),
      )
    Error(Nil) -> State(..state, message: "Nothing to undo.")
  }
}

fn redo(state: State) -> State {
  case game.redo(state.game) {
    Ok(next) ->
      changed(State(..state, game: next, selection: None, message: "Redone."))
    Error(Nil) -> State(..state, message: "Nothing to redo.")
  }
}

fn deal_next(state: State) -> State {
  let counted = give_up(state)
  let #(number, seed) = deck.next_game_number(counted.seed)
  changed(
    State(
      ..counted,
      game: game.new(number),
      selection: None,
      message: "",
      seed: seed,
      counted: False,
    ),
  )
}

fn toggle_auto_play(state: State) -> State {
  let wanted = !game.auto_play_enabled(state.game)
  note_win(changed(
    State(
      ..state,
      game: game.set_auto_play(state.game, wanted),
      message: case wanted {
        True -> "Auto-play on."
        False -> "Auto-play off."
      },
    ),
  ))
}

/// Add a finished game to the record, once.
fn note_win(state: State) -> State {
  case game.status(state.game) == game.Won && !state.counted {
    True ->
      State(..state, record: stats.record_win(state.record), counted: True)
    False -> state
  }
}

/// Count a game that is being walked away from. A game nobody has moved in
/// does not count as a loss — opening the program and closing it again is not
/// a defeat.
fn give_up(state: State) -> State {
  case state.counted || game.moves(state.game) == 0 {
    True -> state
    False ->
      State(..state, record: stats.record_loss(state.record), counted: True)
  }
}

fn place_for(character: String) -> Result(Location, Nil) {
  case character {
    "1" -> Ok(Cascade(0))
    "2" -> Ok(Cascade(1))
    "3" -> Ok(Cascade(2))
    "4" -> Ok(Cascade(3))
    "5" -> Ok(Cascade(4))
    "6" -> Ok(Cascade(5))
    "7" -> Ok(Cascade(6))
    "8" -> Ok(Cascade(7))
    "a" -> Ok(Free(0))
    "s" -> Ok(Free(1))
    "d" -> Ok(Free(2))
    "f" -> Ok(Free(3))
    _ -> Error(Nil)
  }
}

// --- Asking the solver -----------------------------------------------------

fn think(state: State, want: Wanted) -> Step {
  case state.thinking {
    Some(_) -> Continue(State(..state, message: "Still thinking."))
    None -> {
      let generation = state.generation + 1
      Think(
        State(
          ..state,
          generation: generation,
          thinking: Some(want),
          message: case want {
            AHint -> "Looking for a move…"
            AFinish -> "Looking for a way to finish…"
          },
        ),
        generation,
        game.board(state.game),
        search_budget,
      )
    }
  }
}

fn searched(state: State, generation: Int, outcome: solver.Outcome) -> Step {
  let settled = State(..state, thinking: None)
  case generation == state.generation, state.thinking {
    // The board moved on while the search ran, so its answer is about a
    // position that no longer exists.
    False, _ -> Continue(settled)
    _, None -> Continue(settled)
    True, Some(want) ->
      Continue(case want, outcome {
        AHint, solver.Solved(moves, _) -> suggest(settled, moves)
        AFinish, solver.Solved(moves, _) -> finish(settled, moves)
        AHint, solver.Unsolved(_, _) ->
          State(
            ..settled,
            message: "No way through from here that I can see. Try undoing.",
          )
        AFinish, solver.Unsolved(_, _) ->
          State(
            ..settled,
            message: "I could not find a way to finish this one.",
          )
      })
  }
}

fn suggest(state: State, moves: List(#(Move, Int))) -> State {
  case moves {
    [] -> State(..state, message: "Nothing left to do.")
    [#(move, _), ..] ->
      State(
        ..state,
        message: "Try "
          <> place_name(move.from)
          <> " to "
          <> place_name(move.to)
          <> ".",
      )
  }
}

/// Play the solution out. The search works from the same rules, so a move
/// should never be refused; if one is, stop there rather than pretend.
fn finish(state: State, moves: List(#(Move, Int))) -> State {
  let played =
    list.fold(moves, state, fn(current, entry) {
      let #(move, _) = entry
      case game.play(current.game, move) {
        Ok(#(next, _)) -> note_win(State(..current, game: next))
        Error(_) -> current
      }
    })
  State(
    ..changed(played),
    selection: None,
    message: case game.status(played.game) {
      game.Won -> "Finished."
      _ -> "I could not play that through from here."
    },
  )
}

fn place_name(place: Location) -> String {
  case place {
    Cascade(index) -> "column " <> int.to_string(index + 1)
    Free(index) -> "free cell " <> cell_key(index)
    Foundation(_) -> "the foundations"
  }
}

fn cell_key(index: Int) -> String {
  case index {
    0 -> "a"
    1 -> "s"
    2 -> "d"
    _ -> "f"
  }
}

/// Note that the board has changed, so any search still running is answering
/// about something else.
fn changed(state: State) -> State {
  State(..state, generation: state.generation + 1, thinking: None)
}

/// Why a move was refused, in words a player can act on.
pub fn describe(reason: Illegal) -> String {
  case reason {
    rules.SameLocation -> "That is where it already is."
    rules.NoSuchLocation -> "There is no such place."
    rules.EmptySource -> "Nothing to pick up there."
    rules.FoundationsAreOneWay -> "Cards do not come back off the foundations."
    rules.FreeCellOccupied -> "That free cell is taken."
    rules.WrongSuitForFoundation -> "That foundation is for another suit."
    rules.FoundationNeedsNextRank -> "The foundation wants the next rank up."
    rules.CascadeNeedsNextRankDown -> "Cards stack one rank down."
    rules.CascadeNeedsAlternatingColour -> "Colours must alternate."
    rules.NotASequence -> "Those cards are not a run."
    rules.NotEnoughRoom(room) ->
      "Only "
      <> int.to_string(room)
      <> case room {
        1 -> " card"
        _ -> " cards"
      }
      <> " can move at once — free a cell or a column."
    rules.RunsOnlyBetweenCascades -> "Only one card can go there."
    rules.NoCardsToMove -> "Nothing to move."
  }
}
