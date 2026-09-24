import fixture
import freecell/board.{type Board}
import freecell/card.{Card, Clubs, Diamonds, Hearts, Spades}
import freecell/deck
import freecell/location.{Cascade, Foundation}
import freecell/rules
import freecell/solver
import gleam/int
import gleam/list

fn settle(state: Board) -> Board {
  let #(next, _) = rules.auto_play(state)
  next
}

fn empty_columns() -> List(String) {
  list.repeat("", 8)
}

pub fn aces_always_go_home_test() {
  let board = fixture.board_from(["AS", "AH", "", "", "", "", "", ""])
  let #(after, sent) = rules.auto_play(board)
  assert list.length(sent) == 2
  assert fixture.foundations(after) == "C:0 D:0 H:1 S:1"
  assert fixture.columns(after) == empty_columns()
}

/// Promotion chains: once the ace is up the two becomes promotable, and so on.
pub fn auto_play_keeps_going_while_it_can_test() {
  let board = fixture.board_from(["AD", "2D", "3D", "", "", "", "", ""])
  let #(after, sent) = rules.auto_play(board)
  assert list.map(sent, card.to_code) == ["AD", "2D"]
  // The three waits: no black foundation has reached two yet.
  assert fixture.foundations(after) == "C:0 D:2 H:0 S:0"
  assert fixture.columns(after) == ["", "", "3D", "", "", "", "", ""]
}

/// The distinction that matters: the move is legal either way, but only safe
/// once nothing could still want the card.
pub fn a_card_waits_until_nothing_could_want_it_test() {
  let nearly =
    fixture.board_from(["3H", "", "", "", "", "", "", ""])
    |> fixture.with_foundations([#(Hearts, 2), #(Clubs, 2), #(Spades, 1)])
  assert rules.legal(nearly, rules.Move(Cascade(0), Foundation(Hearts)))
    == Ok(Nil)
  assert !rules.is_safe_to_promote(nearly, Card(3, Hearts))
  let #(held, sent) = rules.auto_play(nearly)
  assert sent == []
  assert fixture.foundations(held) == "C:2 D:0 H:2 S:1"

  let ready =
    fixture.board_from(["3H", "", "", "", "", "", "", ""])
    |> fixture.with_foundations([#(Hearts, 2), #(Clubs, 2), #(Spades, 2)])
  assert rules.is_safe_to_promote(ready, Card(3, Hearts))
  let #(promoted, _) = rules.auto_play(ready)
  assert fixture.foundations(promoted) == "C:2 D:0 H:3 S:2"
}

pub fn aces_and_twos_are_always_safe_test() {
  let bare = fixture.board_from(empty_columns())
  assert rules.is_safe_to_promote(bare, Card(1, Spades))
  assert rules.is_safe_to_promote(bare, Card(2, Spades))
  assert !rules.is_safe_to_promote(bare, Card(3, Spades))
}

pub fn a_fresh_deal_promotes_nothing_test() {
  let assert Ok(dealt) = board.new(deck.deal(1))
  let #(after, sent) = rules.auto_play(dealt)
  assert sent == []
  assert fixture.columns(after) == fixture.columns(dealt)
}

pub fn a_board_is_won_when_every_suit_is_home_test() {
  let complete =
    fixture.board_from(empty_columns())
    |> fixture.with_foundations([
      #(Clubs, 13),
      #(Diamonds, 13),
      #(Hearts, 13),
      #(Spades, 13),
    ])
  assert rules.is_won(complete)
  assert !rules.is_stuck(rules.Standard, complete)

  let almost =
    fixture.board_from(empty_columns())
    |> fixture.with_foundations([
      #(Clubs, 13),
      #(Diamonds, 13),
      #(Hearts, 13),
      #(Spades, 12),
    ])
  assert !rules.is_won(almost)
}

/// Every exposed card is two ranks from every other, the cells are full, and
/// no ace has turned up — so there is nothing left to do.
pub fn a_board_with_no_moves_is_stuck_test() {
  let dead =
    fixture.board_from(["2C", "2D", "2H", "2S", "4C", "4D", "4H", "4S"])
    |> fixture.with_cells(["6C", "6D", "6H", "6S"])
  assert rules.available_moves(rules.Standard, dead) == []
  assert rules.is_stuck(rules.Standard, dead)
  assert !rules.is_won(dead)
}

pub fn a_fresh_deal_is_neither_won_nor_stuck_test() {
  let assert Ok(dealt) = board.new(deck.deal(617))
  assert !rules.is_won(dealt)
  assert !rules.is_stuck(rules.Standard, dealt)
  assert rules.available_moves(rules.Standard, dealt) != []
}

/// The end-to-end check, and the one that matters most: real numbered deals
/// are searched for a solution, and each solution is then replayed from the
/// deal itself to reach a won board. The replay is deliberately independent of
/// the search — it re-applies every move through `apply_run` and `auto_play`
/// from scratch, so a rules engine that miscounted a run, lost a card or
/// mis-detected a win could not get through it.
pub fn real_deals_can_be_played_through_to_a_win_test() {
  list.each([1, 3, 7, 8, 14, 15], fn(game_number) {
    let assert Ok(start) = board.new(deck.deal(game_number))
    let assert solver.Solved(moves, _) =
      solver.solve(rules.Standard, start, 20_000)
      as { "game " <> int.to_string(game_number) <> " should be solvable" }
    assert moves != []

    let finish =
      list.fold(moves, settle(start), fn(state, entry) {
        let #(move, count) = entry
        let assert Ok(next) =
          rules.apply_run(rules.Standard, state, move, count)
        settle(next)
      })

    assert rules.is_won(finish)
    assert board.card_count(finish) == 52
    assert fixture.foundations(finish) == "C:13 D:13 H:13 S:13"
    assert fixture.columns(finish) == empty_columns()
    assert fixture.cells(finish) == [".", ".", ".", "."]
  })
}

/// Game 11982 is the one deal in the Microsoft range with no solution. The
/// search finding none is not a proof — the solver prunes moves that are only
/// mostly redundant — but a rules engine that had started calling losing
/// positions won would fail here loudly.
pub fn the_unsolvable_deal_yields_no_win_test() {
  let assert Ok(start) = board.new(deck.deal(11_982))
  let assert solver.Unsolved(_, _) = solver.solve(rules.Standard, start, 4000)
}
