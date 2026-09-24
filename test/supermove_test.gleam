import fixture
import freecell/board.{type Board}
import freecell/card
import freecell/location.{Cascade, Foundation, Free}
import freecell/rules.{
  Move, NoCardsToMove, NotASequence, NotEnoughRoom, RunsOnlyBetweenCascades,
}

/// Eight occupied columns, so nothing is empty unless a test says so.
fn packed() -> Board {
  fixture.board_from(["KS", "KH", "KD", "KC", "QS", "QH", "QD", "QC"])
}

pub fn capacity_is_one_more_than_the_free_cells_test() {
  assert rules.capacity(packed(), Cascade(0)) == 5

  let three = fixture.with_cells(packed(), ["2C", "", "", ""])
  assert rules.capacity(three, Cascade(0)) == 4

  let none = fixture.with_cells(packed(), ["2C", "2D", "2H", "2S"])
  assert rules.capacity(none, Cascade(0)) == 1
}

/// Each empty column doubles the reach, because a whole sub-run can be parked
/// there rather than a single card.
pub fn empty_columns_double_the_capacity_test() {
  let one_gap =
    fixture.board_from(["KS", "KH", "KD", "KC", "QS", "QH", "QD", ""])
  assert rules.capacity(one_gap, Cascade(0)) == 10

  let two_gaps =
    fixture.board_from(["KS", "KH", "KD", "KC", "QS", "QH", "", ""])
  assert rules.capacity(two_gaps, Cascade(0)) == 20
}

/// Moving into an empty column spends it, so it cannot also stage the run.
pub fn the_destination_column_does_not_count_towards_its_own_capacity_test() {
  let one_gap =
    fixture.board_from(["KS", "KH", "KD", "KC", "QS", "QH", "QD", ""])
  assert rules.capacity(one_gap, Cascade(7)) == 5
  assert rules.capacity(one_gap, Cascade(0)) == 10
}

pub fn run_length_counts_the_descending_alternating_tail_test() {
  let board =
    fixture.board_from(["7H 6S 5D", "7H 6S 5S", "7H 5D", "9C", "", "", "", ""])
  assert rules.run_length(board, Cascade(0)) == 3
  // Same colour breaks the run, so only the exposed card can move.
  assert rules.run_length(board, Cascade(1)) == 1
  // So does a gap in rank.
  assert rules.run_length(board, Cascade(2)) == 1
  assert rules.run_length(board, Cascade(3)) == 1
  assert rules.run_length(board, Cascade(4)) == 0
  assert rules.run_length(board, Foundation(card.Spades)) == 0
}

pub fn a_run_moves_onto_a_matching_anchor_test() {
  let board = fixture.board_from(["7H 6S 5D", "8S", "", "", "", "", "", ""])
  // The seven is what lands on the eight; the six and five ride along.
  let assert Ok(after) = rules.apply_run(board, Move(Cascade(0), Cascade(1)), 3)
  assert fixture.columns(after) == ["", "8S 7H 6S 5D", "", "", "", "", "", ""]
}

pub fn a_run_is_refused_when_its_anchor_does_not_fit_test() {
  let board = fixture.board_from(["7H 6S 5D", "8H", "", "", "", "", "", ""])
  assert rules.apply_run(board, Move(Cascade(0), Cascade(1)), 3)
    == Error(rules.CascadeNeedsAlternatingColour)
}

pub fn only_a_real_sequence_can_move_as_one_test() {
  let board = fixture.board_from(["7H 6S 5S", "8S", "", "", "", "", "", ""])
  assert rules.apply_run(board, Move(Cascade(0), Cascade(1)), 3)
    == Error(NotASequence)
  // Asking for more cards than the column holds is the same complaint.
  assert rules.apply_run(board, Move(Cascade(0), Cascade(1)), 9)
    == Error(NotASequence)
}

pub fn a_run_is_refused_when_there_is_nowhere_to_stage_it_test() {
  let board =
    fixture.board_from(["7H 6S 5D", "8S", "6C", "KH", "KD", "KC", "QS", "QH"])
    |> fixture.with_cells(["2C", "2D", "2H", "2S"])
  assert rules.capacity(board, Cascade(1)) == 1
  assert rules.apply_run(board, Move(Cascade(0), Cascade(1)), 3)
    == Error(NotEnoughRoom(1))

  // A single card never needs staging, so it still moves where it fits.
  let assert Ok(_) = rules.apply_run(board, Move(Cascade(0), Cascade(2)), 1)
}

/// When the run is refused for want of room, say so — rather than reporting
/// whatever went wrong with the last, shortest attempt.
pub fn a_blocked_run_reports_the_lack_of_room_test() {
  let board =
    fixture.board_from(["7H 6S 5D", "8S", "KS", "KH", "KD", "KC", "QS", "QH"])
    |> fixture.with_cells(["2C", "2D", "2H", ""])
  assert rules.capacity(board, Cascade(1)) == 2
  assert rules.apply_run(board, Move(Cascade(0), Cascade(1)), 3)
    == Error(NotEnoughRoom(2))
  assert rules.longest_run(board, Move(Cascade(0), Cascade(1)))
    == Error(NotEnoughRoom(2))
}

pub fn runs_only_move_between_cascades_test() {
  let board = fixture.board_from(["7H 6S 5D", "", "", "", "", "", "", ""])
  assert rules.apply_run(board, Move(Cascade(0), Free(0)), 3)
    == Error(RunsOnlyBetweenCascades)
  assert rules.apply_run(board, Move(Cascade(0), Cascade(0)), 3)
    == Error(rules.SameLocation)
}

pub fn moving_no_cards_is_not_a_move_test() {
  let board = fixture.board_from(["7H 6S 5D", "8S", "", "", "", "", "", ""])
  assert rules.apply_run(board, Move(Cascade(0), Cascade(1)), 0)
    == Error(NoCardsToMove)
  assert rules.apply_run(board, Move(Cascade(0), Cascade(1)), -1)
    == Error(NoCardsToMove)
}

pub fn apply_best_takes_as_many_cards_as_will_go_test() {
  let board = fixture.board_from(["7H 6S 5D", "8S", "", "", "", "", "", ""])
  assert rules.longest_run(board, Move(Cascade(0), Cascade(1))) == Ok(3)

  let assert Ok(#(after, moved)) =
    rules.apply_best(board, Move(Cascade(0), Cascade(1)))
  assert moved == 3
  assert fixture.columns(after) == ["", "8S 7H 6S 5D", "", "", "", "", "", ""]
}

/// The three-run will not land on a red seven, but the two-run will, so that
/// is what moves.
pub fn apply_best_falls_back_to_a_shorter_run_test() {
  let board = fixture.board_from(["7H 6S 5D", "7D", "", "", "", "", "", ""])
  assert rules.run_length(board, Cascade(0)) == 3
  assert rules.longest_run(board, Move(Cascade(0), Cascade(1))) == Ok(2)

  let assert Ok(#(after, moved)) =
    rules.apply_best(board, Move(Cascade(0), Cascade(1)))
  assert moved == 2
  assert fixture.columns(after) == ["7H", "7D 6S 5D", "", "", "", "", "", ""]
}

pub fn a_run_keeps_every_card_test() {
  let board = fixture.board_from(["7H 6S 5D", "8S", "", "", "", "", "", ""])
  let before = board.card_count(board)
  let assert Ok(after) = rules.apply_run(board, Move(Cascade(0), Cascade(1)), 3)
  assert board.card_count(after) == before
}

/// The figure shown to the player, before any destination is chosen: one per
/// free cell plus one, doubled for every empty column.
pub fn carrying_capacity_counts_cells_and_spaces_test() {
  assert rules.carrying_capacity(packed()) == 5

  let no_cells = fixture.with_cells(packed(), ["2C", "2D", "2H", "2S"])
  assert rules.carrying_capacity(no_cells) == 1

  let one_gap =
    fixture.board_from(["KS", "KH", "KD", "KC", "QS", "QH", "QD", ""])
  assert rules.carrying_capacity(one_gap) == 10

  // Into the gap itself it is halved, which `capacity` accounts for and the
  // header deliberately does not.
  assert rules.capacity(one_gap, Cascade(7)) == 5
  assert rules.capacity(one_gap, Cascade(0)) == 10
}
