import fixture
import freecell/board
import freecell/card.{Card, Diamonds, Hearts, Spades}
import freecell/deck
import freecell/location.{Cascade, Foundation, Free}
import gleam/list
import gleam/option.{None, Some}

fn empty_columns() -> List(String) {
  list.repeat("", 8)
}

pub fn new_requires_exactly_eight_columns_test() {
  assert board.new([]) == Error(Nil)
  assert board.new(list.repeat([], 7)) == Error(Nil)
  assert board.new(list.repeat([], 9)) == Error(Nil)
  let assert Ok(_) = board.new(list.repeat([], 8))
}

/// Cascades arrive in printed order and are stored exposed-card-first. Getting
/// this backwards would make every move operate on a buried card.
pub fn cascades_are_stored_exposed_card_first_test() {
  let board = fixture.board_from(["TC 9H", ..list.repeat("", 7)])
  assert board.cascade(board, 0) == Ok(fixture.cards("9H TC"))
  assert board.cascade_display(board, 0) == Ok(fixture.cards("TC 9H"))
  assert board.exposed(board, Cascade(0)) == Ok(Card(9, Hearts))
}

pub fn exposed_reports_nothing_for_empty_places_test() {
  let board = fixture.board_from(empty_columns())
  assert board.exposed(board, Cascade(0)) == Error(Nil)
  assert board.exposed(board, Free(0)) == Error(Nil)
  assert board.exposed(board, Foundation(Hearts)) == Error(Nil)
}

pub fn out_of_range_indices_are_errors_test() {
  let board = fixture.board_from(empty_columns())
  assert board.cascade(board, -1) == Error(Nil)
  assert board.cascade(board, 8) == Error(Nil)
  assert board.free_cell(board, -1) == Error(Nil)
  assert board.free_cell(board, 4) == Error(Nil)
}

pub fn take_lifts_the_exposed_card_test() {
  let board = fixture.board_from(["TC 9H", ..list.repeat("", 7)])
  let assert Ok(#(lifted, rest)) = board.take(board, Cascade(0))
  assert lifted == Card(9, Hearts)
  assert fixture.columns(rest) == ["TC", ..list.repeat("", 7)]
}

pub fn free_cells_hold_one_card_each_test() {
  let board = fixture.board_from(empty_columns())
  assert board.empty_free_cells(board) == 4

  let assert Ok(filled) = board.place(board, Free(1), Card(5, Hearts))
  assert board.free_cell(filled, 1) == Ok(Some(Card(5, Hearts)))
  assert board.empty_free_cells(filled) == 3
  assert board.place(filled, Free(1), Card(6, Spades)) == Error(Nil)

  let assert Ok(#(lifted, emptied)) = board.take(filled, Free(1))
  assert lifted == Card(5, Hearts)
  assert board.free_cell(emptied, 1) == Ok(None)
}

pub fn foundations_start_empty_and_only_take_their_own_suit_test() {
  let board = fixture.board_from(empty_columns())
  assert board.foundation(board, Diamonds) == 0
  assert board.place(board, Foundation(Diamonds), Card(1, Hearts)) == Error(Nil)

  let assert Ok(with_ace) =
    board.place(board, Foundation(Diamonds), Card(1, Diamonds))
  assert board.foundation(with_ace, Diamonds) == 1
  assert fixture.foundations(with_ace) == "C:0 D:1 H:0 S:0"
}

/// Cards go onto foundations and stay there; there is no taking one back.
pub fn foundations_are_one_way_test() {
  let board = fixture.board_from(empty_columns())
  let assert Ok(with_ace) =
    board.place(board, Foundation(Diamonds), Card(1, Diamonds))
  assert board.take(with_ace, Foundation(Diamonds)) == Error(Nil)
}

pub fn empty_cascades_are_counted_test() {
  assert board.empty_cascades(fixture.board_from(empty_columns())) == 8
  assert board.empty_cascades(fixture.board_from(["KS", ..list.repeat("", 7)]))
    == 7
  let assert Ok(dealt) = board.new(deck.deal(1))
  assert board.empty_cascades(dealt) == 0
}

pub fn a_dealt_board_holds_the_whole_deck_test() {
  let assert Ok(dealt) = board.new(deck.deal(1))
  assert board.card_count(dealt) == 52
  assert board.empty_free_cells(dealt) == 4
  assert fixture.foundations(dealt) == "C:0 D:0 H:0 S:0"
}
