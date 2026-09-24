//// Helpers for building and describing boards in tests.
////
//// Not named `*_test`, so gleeunit leaves it alone.

import freecell/board.{type Board}
import freecell/card.{type Card, type Suit}
import freecell/location
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Build a board from eight printed columns, buried card first:
/// `board_from(["KS QH", "", ...])`.
///
/// Asserts rather than returning a Result: a typo in a fixture should stop the
/// test loudly, not quietly produce a different board.
pub fn board_from(columns: List(String)) -> Board {
  let assert Ok(built) = board.new(list.map(columns, cards))
    as "a fixture board needs exactly eight columns"
  built
}

pub fn cards(codes: String) -> List(Card) {
  codes
  |> string.split(" ")
  |> list.filter(fn(code) { code != "" })
  |> list.map(fn(code) {
    let assert Ok(parsed) = card.from_code(code)
      as { "fixture card code should parse: " <> code }
    parsed
  })
}

/// Cascades as printed, buried card first, one string per column.
pub fn columns(board: Board) -> List(String) {
  list.map(board.cascades(board), fn(cascade) {
    cascade |> list.reverse |> list.map(card.to_code) |> string.join(" ")
  })
}

/// Free cells, with "." for an empty one.
pub fn cells(board: Board) -> List(String) {
  list.map(board.free_cells(board), fn(cell) {
    case cell {
      None -> "."
      Some(held) -> card.to_code(held)
    }
  })
}

/// Foundations as "C:0 D:1 H:0 S:0".
pub fn foundations(board: Board) -> String {
  card.suits()
  |> list.map(fn(suit: Suit) {
    card.suit_letter(suit)
    <> ":"
    <> int.to_string(board.foundation(board, suit))
  })
  |> string.join(" ")
}

/// Put cards into free cells, left to right. An empty string leaves that cell
/// alone: `with_cells(board, ["5H", "", "", "KC"])`.
pub fn with_cells(board board: Board, codes codes: List(String)) -> Board {
  list.index_fold(codes, board, fn(acc, code, index) {
    case cards(code) {
      [held] -> {
        let assert Ok(filled) = board.place(acc, location.Free(index), held)
          as { "free cell " <> int.to_string(index) <> " should be empty" }
        filled
      }
      _ -> acc
    }
  })
}

/// Set foundations straight to a rank, skipping the cards underneath. Only
/// sound for testing states that do not care how they were reached.
pub fn with_foundations(
  board board: Board,
  piles piles: List(#(Suit, Int)),
) -> Board {
  list.fold(piles, board, fn(acc, pile) {
    let #(suit, rank) = pile
    case rank {
      0 -> acc
      _ -> {
        let assert Ok(stacked) =
          board.place(acc, location.Foundation(suit), card.Card(rank, suit))
        stacked
      }
    }
  })
}
