//// Whether a move is allowed, and carrying it out.
////
//// Phase 2 covers single cards only. Moving a run of several cards at once is
//// built on top of this in `rules`' supermove support.

import freecell/board.{type Board}
import freecell/card.{type Card}
import freecell/location.{type Location, Cascade, Foundation, Free}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type Move {
  Move(from: Location, to: Location)
}

/// Which rules are being played by.
pub type Mode {
  /// The real game: a run only moves if there is somewhere to stage it, one
  /// card at a time, in free cells and empty columns.
  Standard
  /// Runs move whole however little room there is. The staging is the part of
  /// FreeCell that is bookkeeping rather than thinking, and some players would
  /// rather not do it.
  Relaxed
}

/// More than any run can be: thirteen cards is a whole suit.
const no_limit = 52

/// Why a move was refused. Kept fine-grained so the interface can say what is
/// actually wrong rather than just beeping.
pub type Illegal {
  SameLocation
  NoSuchLocation
  EmptySource
  FoundationsAreOneWay
  FreeCellOccupied
  WrongSuitForFoundation
  FoundationNeedsNextRank
  CascadeNeedsNextRankDown
  CascadeNeedsAlternatingColour
  /// The cards being moved are not a descending, alternating-colour run.
  NotASequence
  /// Too few free cells and empty columns to shuffle the run across.
  NotEnoughRoom(capacity: Int)
  /// Runs of more than one card only ever move cascade to cascade.
  RunsOnlyBetweenCascades
  NoCardsToMove
}

/// Carry out a move, or explain why it cannot happen.
pub fn apply(board board: Board, move move: Move) -> Result(Board, Illegal) {
  case move.from == move.to {
    True -> Error(SameLocation)
    False ->
      case board.take(board, move.from) {
        Error(Nil) -> Error(refusal_for_source(board, move.from))
        Ok(#(moving, lifted)) -> {
          // Check the destination against the board *after* lifting, so a card
          // is never judged against its own former position.
          use Nil <- result.try(check_destination(lifted, move.to, moving))
          board.place(lifted, move.to, moving)
          |> result.replace_error(NoSuchLocation)
        }
      }
  }
}

/// Whether a move is allowed. Defined as "applying it works", so there is no
/// second copy of the rules to drift out of step.
pub fn legal(board board: Board, move move: Move) -> Result(Nil, Illegal) {
  apply(board, move) |> result.replace(Nil)
}

/// True when `moving` may be stacked directly onto `onto` in a cascade:
/// one rank lower, and the opposite colour.
pub fn can_stack(moving: Card, onto: Card) -> Bool {
  stacks_on(moving, onto) == Ok(Nil)
}

/// Every single-card move currently available.
///
/// Equivalent destinations are all listed separately — four empty free cells
/// give four entries for the same effective move. Callers that care about
/// distinctness must fold them together themselves.
pub fn legal_moves(board: Board) -> List(Move) {
  list.flat_map(sources(), fn(from) {
    list.filter_map(destinations(), fn(to) {
      case legal(board, Move(from, to)) {
        Ok(Nil) -> Ok(Move(from, to))
        Error(_) -> Error(Nil)
      }
    })
  })
}

// --- Internals -------------------------------------------------------------

fn check_destination(
  board: Board,
  to: Location,
  moving: Card,
) -> Result(Nil, Illegal) {
  case to {
    Free(index) ->
      case board.free_cell(board, index) {
        Error(Nil) -> Error(NoSuchLocation)
        Ok(Some(_)) -> Error(FreeCellOccupied)
        Ok(None) -> Ok(Nil)
      }

    Foundation(suit) ->
      case suit == moving.suit {
        False -> Error(WrongSuitForFoundation)
        True ->
          case board.foundation(board, suit) == moving.rank - 1 {
            True -> Ok(Nil)
            False -> Error(FoundationNeedsNextRank)
          }
      }

    Cascade(index) ->
      case board.cascade(board, index) {
        Error(Nil) -> Error(NoSuchLocation)
        // An empty cascade accepts any single card.
        Ok([]) -> Ok(Nil)
        Ok([onto, ..]) -> stacks_on(moving, onto)
      }
  }
}

fn stacks_on(moving: Card, onto: Card) -> Result(Nil, Illegal) {
  case onto.rank == moving.rank + 1 {
    False -> Error(CascadeNeedsNextRankDown)
    True ->
      case card.alternates(moving, onto) {
        False -> Error(CascadeNeedsAlternatingColour)
        True -> Ok(Nil)
      }
  }
}

/// `board.take` reports only that it failed; this works out why, so the player
/// gets a useful message. The branches for a source that does hold a card are
/// unreachable — had it held one, `take` would have succeeded.
fn refusal_for_source(board: Board, from: Location) -> Illegal {
  case from {
    Foundation(_) -> FoundationsAreOneWay
    Cascade(index) ->
      case board.cascade(board, index) {
        Error(Nil) -> NoSuchLocation
        Ok([]) -> EmptySource
        Ok([_, ..]) -> NoSuchLocation
      }
    Free(index) ->
      case board.free_cell(board, index) {
        Error(Nil) -> NoSuchLocation
        Ok(None) -> EmptySource
        Ok(Some(_)) -> NoSuchLocation
      }
  }
}

fn sources() -> List(Location) {
  list.append(
    list.map(indices(board.cascade_count), Cascade),
    list.map(indices(board.free_cell_count), Free),
  )
}

fn destinations() -> List(Location) {
  list.append(sources(), list.map(card.suits(), Foundation))
}

fn indices(count: Int) -> List(Int) {
  int.range(from: count - 1, to: -1, with: [], run: fn(acc, index) {
    [index, ..acc]
  })
}

// --- Runs of several cards -------------------------------------------------

/// How many cards may be carried as a unit onto `into`.
///
/// A run is really moved one card at a time, parking the surplus: every free
/// cell holds one spare card, and every empty column can hold a whole
/// sub-run, which doubles the reach. Hence `(free + 1) * 2^empty`.
///
/// Moving *into* an empty column costs you that column as staging space, so it
/// does not count towards the doubling.
pub fn capacity(
  mode mode: Mode,
  board board: Board,
  into into: Location,
) -> Int {
  case mode {
    Relaxed -> no_limit
    Standard -> standard_capacity(board, into)
  }
}

fn standard_capacity(board: Board, into: Location) -> Int {
  case into {
    Cascade(index) ->
      case board.cascade(board, index) {
        // An empty destination is spent by the move, so it cannot also stage
        // it. Losing one doubling is exactly halving.
        Ok([]) -> int.max(carrying_capacity(board) / 2, 1)
        _ -> carrying_capacity(board)
      }
    _ -> carrying_capacity(board)
  }
}

/// How many cards can travel as one onto a column that is not empty.
///
/// This is the number worth showing a player: one for each free cell plus one
/// for the card itself, doubled for every empty column. It is also the number
/// that surprises them — with every cell full and no empty column it is 1, and
/// then cards really do move one at a time.
/// The carrying capacity as it is worth telling a player.
///
/// A run can never be longer than a full suit, so a board with several empty
/// columns reports numbers in the hundreds that mean nothing. The cap is for
/// display only: `capacity` needs the true figure, because halving it for an
/// empty destination has to halve the real number.
pub fn shown_capacity(board: Board) -> Int {
  int.min(carrying_capacity(board), card.king)
}

pub fn carrying_capacity(board: Board) -> Int {
  { board.empty_free_cells(board) + 1 }
  * int.bitwise_shift_left(1, board.empty_cascades(board))
}

/// How many cards at the exposed end of `from` form a movable run.
pub fn run_length(board board: Board, from from: Location) -> Int {
  case from {
    Foundation(_) -> 0
    Free(index) ->
      case board.free_cell(board, index) {
        Ok(Some(_)) -> 1
        _ -> 0
      }
    Cascade(index) ->
      case board.cascade(board, index) {
        Ok(cards) -> sequence_length(cards)
        Error(Nil) -> 0
      }
  }
}

/// Move `count` cards as a unit.
pub fn apply_run(
  mode mode: Mode,
  board board: Board,
  move move: Move,
  count count: Int,
) -> Result(Board, Illegal) {
  case count {
    n if n < 1 -> Error(NoCardsToMove)
    1 -> apply(board, move)
    n -> apply_multi(mode, board, move, n)
  }
}

/// The largest run that can legally make this move, or why none can.
pub fn longest_run(
  mode mode: Mode,
  board board: Board,
  move move: Move,
) -> Result(Int, Illegal) {
  largest_run(mode, board, move, run_length(board, move.from))
}

/// Make the move with as many cards as will go, reporting how many moved.
pub fn apply_best(
  mode mode: Mode,
  board board: Board,
  move move: Move,
) -> Result(#(Board, Int), Illegal) {
  use count <- result.try(longest_run(mode, board, move))
  use moved <- result.try(apply_run(mode, board, move, count))
  Ok(#(moved, count))
}

fn largest_run(
  mode: Mode,
  board: Board,
  move: Move,
  count: Int,
) -> Result(Int, Illegal) {
  case count < 1 {
    // Nothing to lift at all; ask for one card to get the real reason.
    True -> apply(board, move) |> result.replace(1)
    False -> try_counts(mode, board, move, count, None)
  }
}

/// Try the longest run first and work down. When nothing fits, report the
/// *first* refusal rather than the last: the player reached for the whole run,
/// so "there is not enough room for it" is the useful answer, not a complaint
/// about the single card that was tried last.
fn try_counts(
  mode: Mode,
  board: Board,
  move: Move,
  count: Int,
  refusal: Option(Illegal),
) -> Result(Int, Illegal) {
  case count < 1 {
    True ->
      case refusal {
        Some(reason) -> Error(reason)
        None -> Error(NoCardsToMove)
      }
    False ->
      case apply_run(mode, board, move, count) {
        Ok(_) -> Ok(count)
        Error(reason) ->
          try_counts(mode, board, move, count - 1, case refusal {
            None -> Some(reason)
            kept -> kept
          })
      }
  }
}

fn apply_multi(
  mode: Mode,
  board: Board,
  move: Move,
  count: Int,
) -> Result(Board, Illegal) {
  case move.from, move.to {
    Cascade(source), Cascade(target) -> {
      case source == target {
        True -> Error(SameLocation)
        False -> {
          use cards <- result.try(
            board.cascade(board, source) |> result.replace_error(NoSuchLocation),
          )
          use Nil <- result.try(
            board.cascade(board, target)
            |> result.replace_error(NoSuchLocation)
            |> result.replace(Nil),
          )
          let #(run, _) = list.split(cards, count)
          use Nil <- result.try(check_run(run, count))
          use Nil <- result.try(check_capacity(mode, board, move.to, count))
          // The deepest card of the run is the one that touches the
          // destination; the rest ride along on top of it.
          let assert Ok(anchor) = list.last(run)
            as "a checked run always has a last card"
          use Nil <- result.try(check_destination(board, move.to, anchor))
          carry(board, move, run)
          |> result.replace_error(NoSuchLocation)
        }
      }
    }
    _, _ -> Error(RunsOnlyBetweenCascades)
  }
}

fn check_run(run: List(Card), count: Int) -> Result(Nil, Illegal) {
  case list.length(run) == count && sequence_length(run) >= count {
    True -> Ok(Nil)
    False -> Error(NotASequence)
  }
}

fn check_capacity(
  mode: Mode,
  board: Board,
  into: Location,
  count: Int,
) -> Result(Nil, Illegal) {
  let room = capacity(mode, board, into)
  case count <= room {
    True -> Ok(Nil)
    False -> Error(NotEnoughRoom(room))
  }
}

/// Lift the run a card at a time and lay it back down deepest first, so it
/// arrives in the same order it left.
fn carry(board: Board, move: Move, run: List(Card)) -> Result(Board, Nil) {
  use #(_, stripped) <- result.try(lift(board, move.from, list.length(run), []))
  place_all(stripped, move.to, list.reverse(run))
}

fn lift(
  state: Board,
  from: Location,
  count: Int,
  taken: List(Card),
) -> Result(#(List(Card), Board), Nil) {
  case count <= 0 {
    True -> Ok(#(list.reverse(taken), state))
    False -> {
      use #(card_taken, rest) <- result.try(board.take(state, from))
      lift(rest, from, count - 1, [card_taken, ..taken])
    }
  }
}

fn place_all(
  state: Board,
  to: Location,
  cards: List(Card),
) -> Result(Board, Nil) {
  case cards {
    [] -> Ok(state)
    [next, ..rest] -> {
      use placed <- result.try(board.place(state, to, next))
      place_all(placed, to, rest)
    }
  }
}

/// Length of the descending, alternating-colour run at the head of the list.
fn sequence_length(cards: List(Card)) -> Int {
  case cards {
    [] -> 0
    [_] -> 1
    [first, second, ..rest] ->
      case can_stack(first, second) {
        True -> 1 + sequence_length([second, ..rest])
        False -> 1
      }
  }
}

// --- Sending cards home ----------------------------------------------------

/// Whether a card can go home without anyone missing it later.
///
/// A red six is only wanted on a cascade by a black five or a black seven.
/// Once both black foundations have reached five, no black card below six is
/// still in play, so the red six can never be needed again. Aces and twos are
/// unconditionally safe: nothing can ever want to stack on them usefully.
pub fn is_safe_to_promote(board board: Board, card moving: Card) -> Bool {
  case moving.rank <= 2 {
    True -> True
    False ->
      card.suits()
      |> list.filter(fn(suit) { card.color(suit) != card.color(moving.suit) })
      |> list.all(fn(suit) { board.foundation(board, suit) >= moving.rank - 1 })
  }
}

/// Send every safely promotable card home, repeating until nothing more is
/// safe. Returns the cards that went, in the order they went.
pub fn auto_play(board: Board) -> #(Board, List(Card)) {
  auto_play_loop(board, [])
}

fn auto_play_loop(state: Board, sent: List(Card)) -> #(Board, List(Card)) {
  case next_safe_promotion(state) {
    Error(Nil) -> #(state, list.reverse(sent))
    Ok(#(next, promoted)) -> auto_play_loop(next, [promoted, ..sent])
  }
}

fn next_safe_promotion(state: Board) -> Result(#(Board, Card), Nil) {
  sources()
  |> list.filter_map(fn(from) {
    use moving <- result.try(board.exposed(state, from))
    case is_safe_to_promote(state, moving) {
      False -> Error(Nil)
      True ->
        apply(state, Move(from, Foundation(moving.suit)))
        |> result.replace_error(Nil)
        |> result.map(fn(next) { #(next, moving) })
    }
  })
  |> list.first
}

// --- How the game stands ---------------------------------------------------

/// True when nothing stands in the way any more: safe auto-play alone would
/// carry every remaining card home. The game is decided, but not yet over.
pub fn is_certain(board: Board) -> Bool {
  let #(settled, _) = auto_play(board)
  is_won(settled)
}

pub fn is_won(board: Board) -> Bool {
  list.all(card.suits(), fn(suit) { board.foundation(board, suit) == card.king })
}

/// Every move available, each with the number of cards it would carry.
///
/// As with `legal_moves`, equivalent destinations are listed separately.
pub fn available_moves(mode: Mode, board: Board) -> List(#(Move, Int)) {
  list.flat_map(sources(), fn(from) {
    list.filter_map(destinations(), fn(to) {
      let move = Move(from, to)
      case longest_run(mode, board, move) {
        Ok(count) -> Ok(#(move, count))
        Error(_) -> Error(Nil)
      }
    })
  })
}

/// Lost: nothing left to try, and the game is not won.
pub fn is_stuck(mode: Mode, board: Board) -> Bool {
  !is_won(board) && available_moves(mode, board) == []
}
