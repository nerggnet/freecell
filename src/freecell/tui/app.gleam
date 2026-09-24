//// What each keypress does.
////
//// Pure. The loop that reads keys and paints the screen lives in `freecell`;
//// everything here is a plain function from state and key to new state, which
//// is what makes the interface testable without a terminal.

import freecell/board.{type Board}
import freecell/deck
import freecell/game.{type Game}
import freecell/location.{type Location, Cascade, Foundation, Free}
import freecell/render.{type Options, type View, Selection, View}
import freecell/rules.{type Illegal, type Move, Move}
import freecell/solver
import freecell/stats.{type Stats}
import freecell/tui/key.{
  type Key, Backspace, Char, Ctrl, Down, Enter, Escape, Space, Up,
}
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
    /// How many cards are held. `None` means "as many as will go", which is
    /// what picking a column up gives you; the arrow keys make it explicit.
    held: Option(Int),
    message: String,
    mode: Mode,
    seed: Int,
    options: Options,
    record: Stats,
    thinking: Option(Thinking),
    /// The clock is supplied from outside rather than read here, so that
    /// deciding what a keypress does stays a pure function of its inputs.
    started_at: Int,
    now: Int,
    /// Set once a game has been played under the relaxed rules, and never
    /// cleared until the next deal. Such a game is left out of the record:
    /// counting both kinds together would make the record mean two things.
    unranked: Bool,
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
  Think(
    state: State,
    generation: Int,
    mode: rules.Mode,
    board: Board,
    budget: Int,
  )
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

/// A search in flight: what it is for, and how hard it is looking.
type Thinking {
  Thinking(want: Wanted, budget: Int)
}

/// The first look. Answers about nine deals in ten, nearly always inside a
/// tenth of a second.
const first_look = 20_000

/// The second look, for when the first finds nothing.
///
/// A deal the first pass gives up on is very rarely unwinnable — of the 32,000
/// numbered deals only one has no solution at all — so refusing there would be
/// telling the player something untrue. At this budget the search reaches
/// about 98% of deals. It can take twenty seconds, which costs the easy cases
/// nothing because they never get here, and costs the hard ones only waiting,
/// because the search runs off the event loop and the game stays playable.
const longer_look = 200_000

pub fn new(
  number: Int,
  seed: Int,
  options: Options,
  record: Stats,
  now: Int,
  mode: rules.Mode,
) -> State {
  State(
    game: game.new(number, mode),
    selection: None,
    held: None,
    message: "Pick a column with 1-8, or ? for the keys.",
    mode: Playing,
    seed:,
    options:,
    record:,
    counted: False,
    thinking: None,
    generation: 0,
    started_at: now,
    now: now,
    unranked: mode == rules.Relaxed,
  )
}

pub fn mode(state: State) -> rules.Mode {
  game.mode(state.game)
}

/// Tell the game what time it is. The loop does this before each frame.
pub fn at(state: State, now: Int) -> State {
  State(..state, now: now)
}

fn elapsed(state: State) -> Int {
  int.max(state.now - state.started_at, 0) / 1_000_000
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
      selection: case state.selection {
        None -> None
        Some(place) -> Some(Selection(place, cards_held(state)))
      },
      message: state.message,
      elapsed: elapsed(state),
      carry: case game.mode(state.game) {
        rules.Relaxed -> None
        rules.Standard -> Some(rules.carrying_capacity(game.board(state.game)))
      },
      stuck: game.status(state.game) == game.Stuck,
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
    Char("m") -> Continue(toggle_mode(state))
    Char("h") -> think(state, AHint)
    Char("!") -> think(state, AFinish)
    Char("u") -> Continue(undo(state))
    Char("r") -> Continue(redo(state))
    Char("n") -> Continue(deal_next(state))
    Char("R") -> Continue(restart(state))
    Escape | Backspace ->
      Continue(State(..state, selection: None, held: None, message: ""))
    Up -> Continue(take(state, 1))
    Down -> Continue(take(state, -1))
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
        Ok(_) ->
          State(..state, selection: Some(target), held: None, message: "")
        Error(Nil) -> State(..state, message: "Nothing to pick up there.")
      }
    Some(source) if source == target ->
      State(..state, selection: None, held: None, message: "Put back.")
    Some(source) -> attempt(state, source, target)
  }
}

fn send_home(state: State) -> State {
  case state.selection {
    None -> State(..state, message: "Pick a card up first.")
    Some(source) ->
      case board.exposed(game.board(state.game), source) {
        Error(Nil) -> State(..state, selection: None, held: None, message: "")
        Ok(moving) -> attempt(state, source, Foundation(moving.suit))
      }
  }
}

/// How many cards the player is holding, which is the whole movable run
/// unless they have said otherwise.
fn cards_held(state: State) -> Int {
  case state.selection {
    None -> 0
    Some(place) ->
      case state.held {
        Some(count) -> count
        None -> rules.run_length(game.board(state.game), place)
      }
  }
}

/// Take one more or one fewer card. Only a column ever holds more than one, so
/// elsewhere this has nothing to do.
fn take(state: State, step: Int) -> State {
  case state.selection {
    None -> State(..state, message: "Pick a card up first.")
    Some(place) -> {
      let most = rules.run_length(game.board(state.game), place)
      let wanted = int.min(int.max(cards_held(state) + step, 1), most)
      State(..state, held: Some(wanted), message: case most {
        1 -> "Only one card can travel from there."
        _ ->
          "Holding "
          <> int.to_string(wanted)
          <> " of "
          <> int.to_string(most)
          <> "."
      })
    }
  }
}

fn attempt(state: State, source: Location, target: Location) -> State {
  let outcome = case state.held {
    // Untouched: carry as many as will go.
    None -> game.play(state.game, Move(source, target))
    // The player chose a number, so hold them to it.
    Some(count) -> game.play_run(state.game, Move(source, target), count)
  }
  case outcome {
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
      game: game.new(number, game.mode(state.game)),
      selection: None,
      held: None,
      message: "",
      seed: seed,
      counted: False,
      unranked: game.mode(state.game) == rules.Relaxed,
      started_at: state.now,
    ),
  )
}

/// Deal the same game again. Like walking away to a new one, this counts as a
/// game given up: otherwise a streak could be kept alive indefinitely by
/// restarting whenever a deal turned awkward.
fn restart(state: State) -> State {
  let counted = give_up(state)
  changed(
    State(
      ..counted,
      game: game.new(game.number(state.game), game.mode(state.game)),
      selection: None,
      held: None,
      message: "Dealt again.",
      counted: False,
      unranked: game.mode(state.game) == rules.Relaxed,
      started_at: state.now,
    ),
  )
}

/// Switch between the standard and relaxed rules. Positions legal under one
/// are legal under the other, so nothing on the board has to change — only
/// what may be moved next.
fn toggle_mode(state: State) -> State {
  let wanted = case game.mode(state.game) {
    rules.Standard -> rules.Relaxed
    rules.Relaxed -> rules.Standard
  }
  State(
    ..changed(State(..state, game: game.set_mode(state.game, wanted))),
    unranked: state.unranked || wanted == rules.Relaxed,
    message: case wanted, state.unranked {
      rules.Relaxed, _ -> "Relaxed rules. This game will not be recorded."
      rules.Standard, True -> "Standard rules. This game is still not recorded."
      rules.Standard, False -> "Standard rules."
    },
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
  case
    game.status(state.game) == game.Won && !state.counted && !state.unranked
  {
    True ->
      State(..state, record: stats.record_win(state.record), counted: True)
    False -> state
  }
}

/// Count a game that is being walked away from. A game nobody has moved in
/// does not count as a loss — opening the program and closing it again is not
/// a defeat.
fn give_up(state: State) -> State {
  case state.counted || state.unranked || game.moves(state.game) == 0 {
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
    None ->
      look(state, want, first_look, case want {
        AHint -> "Looking for a move…"
        AFinish -> "Looking for a way to finish…"
      })
  }
}

fn look(state: State, want: Wanted, budget: Int, message: String) -> Step {
  let generation = state.generation + 1
  Think(
    State(
      ..state,
      generation: generation,
      thinking: Some(Thinking(want, budget)),
      message: message,
    ),
    generation,
    game.mode(state.game),
    game.board(state.game),
    budget,
  )
}

fn searched(state: State, generation: Int, outcome: solver.Outcome) -> Step {
  let settled = State(..state, thinking: None)
  case generation == state.generation, state.thinking {
    // The board moved on while the search ran, so its answer is about a
    // position that no longer exists.
    False, _ -> Continue(settled)
    _, None -> Continue(settled)
    True, Some(Thinking(want, budget)) ->
      case outcome {
        solver.Solved(moves, _) ->
          Continue(case want {
            AHint -> suggest(settled, moves)
            AFinish -> finish(settled, moves)
          })
        // Nothing yet. Look harder before saying there is nothing to find:
        // most positions the first pass gives up on yield to a longer look,
        // and the player is owed the difference between "no" and "not yet".
        solver.Unsolved(_, _) ->
          case budget < longer_look {
            True ->
              look(
                settled,
                want,
                longer_look,
                "Nothing obvious yet — looking harder…",
              )
            False ->
              Continue(
                State(..settled, message: case want {
                  AHint ->
                    "No way through from here that I can see. Try undoing."
                  AFinish -> "I could not find a way to finish this one."
                }),
              )
          }
      }
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
