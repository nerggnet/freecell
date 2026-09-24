//// The board: eight cascades, four free cells, four foundations.
////
//// This module owns the *shape* of the game — what a card can physically sit
//// on — and nothing about whether a move is allowed. Legality lives in
//// `freecell/rules`.

import freecell/card.{type Card, type Suit}
import freecell/location.{type Location, Cascade, Foundation, Free}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub const cascade_count = 8

pub const free_cell_count = 4

/// Cascades are stored **exposed card first**, which is the reverse of how
/// they are printed and of what `deck.deal` hands us. Storing them this way
/// makes every move a head operation and a plain pattern match; `new` does the
/// one reversal, and `cascade_display` undoes it for the renderer.
///
/// Foundations map a suit to its highest placed rank. A missing key means the
/// pile is empty, which `foundation` reports as rank 0.
pub opaque type Board {
  Board(
    cascades: List(List(Card)),
    free_cells: List(Option(Card)),
    foundations: Dict(Suit, Int),
  )
}

/// Build a board from dealt columns in printed order, buried card first.
pub fn new(columns: List(List(Card))) -> Result(Board, Nil) {
  case list.length(columns) == cascade_count {
    False -> Error(Nil)
    True ->
      Ok(Board(
        cascades: list.map(columns, list.reverse),
        free_cells: list.repeat(None, free_cell_count),
        foundations: dict.new(),
      ))
  }
}

// --- Reading ---------------------------------------------------------------

/// A cascade, exposed card first.
pub fn cascade(board: Board, index: Int) -> Result(List(Card), Nil) {
  at(board.cascades, index)
}

/// A cascade as it appears on screen, buried card first.
pub fn cascade_display(board: Board, index: Int) -> Result(List(Card), Nil) {
  cascade(board, index) |> result.map(list.reverse)
}

pub fn cascades(board: Board) -> List(List(Card)) {
  board.cascades
}

pub fn free_cell(board: Board, index: Int) -> Result(Option(Card), Nil) {
  at(board.free_cells, index)
}

pub fn free_cells(board: Board) -> List(Option(Card)) {
  board.free_cells
}

/// The highest rank placed on a suit's foundation, or 0 when it is empty.
pub fn foundation(board: Board, suit: Suit) -> Int {
  dict.get(board.foundations, suit) |> result.unwrap(0)
}

/// The exposed card at a location, if there is one.
pub fn exposed(board: Board, at location: Location) -> Result(Card, Nil) {
  case location {
    Cascade(index) ->
      case cascade(board, index) {
        Ok([top, ..]) -> Ok(top)
        _ -> Error(Nil)
      }
    Free(index) ->
      case free_cell(board, index) {
        Ok(Some(card)) -> Ok(card)
        _ -> Error(Nil)
      }
    Foundation(suit) ->
      case foundation(board, suit) {
        0 -> Error(Nil)
        rank -> Ok(card.Card(rank, suit))
      }
  }
}

pub fn empty_free_cells(board: Board) -> Int {
  list.count(board.free_cells, fn(cell) { cell == None })
}

pub fn empty_cascades(board: Board) -> Int {
  list.count(board.cascades, list.is_empty)
}

/// Total cards on the board. Always 52 for a board built by `new`; used by
/// tests to prove that moving cards never creates or loses one.
pub fn card_count(board: Board) -> Int {
  let in_cascades =
    list.fold(board.cascades, 0, fn(sum, c) { sum + list.length(c) })
  let in_cells = free_cell_count - empty_free_cells(board)
  let on_foundations =
    list.fold(card.suits(), 0, fn(sum, suit) { sum + foundation(board, suit) })
  in_cascades + in_cells + on_foundations
}

// --- Moving ----------------------------------------------------------------

/// Lift the exposed card off a location. Says nothing about whether doing so
/// is a legal move — that is `rules`' job. Foundations are one-way, so taking
/// from one always fails.
pub fn take(board: Board, from: Location) -> Result(#(Card, Board), Nil) {
  case from {
    Foundation(_) -> Error(Nil)
    Free(index) -> {
      use cell <- result.try(free_cell(board, index))
      case cell {
        None -> Error(Nil)
        Some(card) ->
          Ok(#(
            card,
            Board(
              ..board,
              free_cells: replace_at(board.free_cells, index, None),
            ),
          ))
      }
    }
    Cascade(index) -> {
      use cards <- result.try(cascade(board, index))
      case cards {
        [] -> Error(Nil)
        [top, ..rest] ->
          Ok(#(
            top,
            Board(..board, cascades: replace_at(board.cascades, index, rest)),
          ))
      }
    }
  }
}

/// Put a card onto a location. Enforces only what is structurally impossible
/// (an occupied cell, a foundation of the wrong suit), not the rules of play.
pub fn place(
  board: Board,
  to: Location,
  card_to_place: Card,
) -> Result(Board, Nil) {
  case to {
    Free(index) -> {
      use cell <- result.try(free_cell(board, index))
      case cell {
        Some(_) -> Error(Nil)
        None ->
          Ok(
            Board(
              ..board,
              free_cells: replace_at(
                board.free_cells,
                index,
                Some(card_to_place),
              ),
            ),
          )
      }
    }
    Foundation(suit) ->
      case suit == card_to_place.suit {
        False -> Error(Nil)
        True ->
          Ok(
            Board(
              ..board,
              foundations: dict.insert(
                board.foundations,
                suit,
                card_to_place.rank,
              ),
            ),
          )
      }
    Cascade(index) -> {
      use cards <- result.try(cascade(board, index))
      Ok(
        Board(
          ..board,
          cascades: replace_at(board.cascades, index, [card_to_place, ..cards]),
        ),
      )
    }
  }
}

// --- Small list helpers ----------------------------------------------------

fn at(items: List(a), index: Int) -> Result(a, Nil) {
  case index < 0 {
    True -> Error(Nil)
    False -> items |> list.drop(index) |> list.first
  }
}

fn replace_at(items: List(a), index: Int, value: a) -> List(a) {
  list.index_map(items, fn(item, position) {
    case position == index {
      True -> value
      False -> item
    }
  })
}
