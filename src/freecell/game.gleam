//// A game in progress: the board, how it got there, and how to take it back.
////
//// Still pure. Undo works by keeping past boards rather than by inverting
//// moves — boards are immutable and share most of their structure, so holding
//// on to every one of them is cheap and cannot drift out of step with the
//// move that produced it.

import freecell/board.{type Board}
import freecell/deck
import freecell/rules.{type Illegal, type Move}
import gleam/result

pub type Status {
  Playing
  Won
  Stuck
}

pub opaque type Game {
  Game(
    number: Int,
    board: Board,
    past: List(Board),
    future: List(Board),
    moves: Int,
    autoplay: Bool,
  )
}

/// Deal a numbered game.
pub fn new(number: Int) -> Game {
  let assert Ok(dealt) = board.new(deck.deal(number))
    as "a deal always produces eight columns"
  Game(number:, board: dealt, past: [], future: [], moves: 0, autoplay: True)
}

pub fn board(game: Game) -> Board {
  game.board
}

pub fn number(game: Game) -> Int {
  game.number
}

pub fn moves(game: Game) -> Int {
  game.moves
}

pub fn auto_play_enabled(game: Game) -> Bool {
  game.autoplay
}

pub fn status(game: Game) -> Status {
  case rules.is_won(game.board), rules.is_stuck(game.board) {
    True, _ -> Won
    _, True -> Stuck
    _, _ -> Playing
  }
}

/// Make a move, carrying as many cards as will go, and report how many went.
pub fn play(game: Game, move: Move) -> Result(#(Game, Int), Illegal) {
  use #(moved, count) <- result.try(rules.apply_best(game.board, move))
  let settled = case game.autoplay {
    True -> {
      let #(after, _) = rules.auto_play(moved)
      after
    }
    False -> moved
  }
  Ok(#(
    Game(
      ..game,
      board: settled,
      past: [game.board, ..game.past],
      future: [],
      moves: game.moves + 1,
    ),
    count,
  ))
}

pub fn can_undo(game: Game) -> Bool {
  game.past != []
}

pub fn can_redo(game: Game) -> Bool {
  game.future != []
}

pub fn undo(game: Game) -> Result(Game, Nil) {
  case game.past {
    [] -> Error(Nil)
    [previous, ..earlier] ->
      Ok(
        Game(
          ..game,
          board: previous,
          past: earlier,
          future: [game.board, ..game.future],
          moves: game.moves - 1,
        ),
      )
  }
}

pub fn redo(game: Game) -> Result(Game, Nil) {
  case game.future {
    [] -> Error(Nil)
    [next, ..later] ->
      Ok(
        Game(
          ..game,
          board: next,
          past: [game.board, ..game.past],
          future: later,
          moves: game.moves + 1,
        ),
      )
  }
}

/// Turning auto-play on sends home whatever is already safe, so the board
/// never sits in a state the setting says should not happen.
pub fn set_auto_play(game: Game, enabled: Bool) -> Game {
  case enabled {
    False -> Game(..game, autoplay: False)
    True -> {
      let #(settled, _) = rules.auto_play(game.board)
      Game(..game, autoplay: True, board: settled)
    }
  }
}
