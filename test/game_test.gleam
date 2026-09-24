import fixture
import freecell/board
import freecell/deck
import freecell/game
import freecell/location.{Cascade, Free}
import freecell/rules.{CascadeNeedsNextRankDown, Move}
import freecell/solver
import gleam/list

pub fn a_new_game_is_the_deal_untouched_test() {
  let fresh = game.new(1, rules.Standard)
  let assert Ok(dealt) = board.new(deck.deal(1))
  assert fixture.columns(game.board(fresh)) == fixture.columns(dealt)
  assert game.moves(fresh) == 0
  assert game.number(fresh) == 1
  assert game.status(fresh) == game.Playing
  assert !game.can_undo(fresh)
  assert !game.can_redo(fresh)
}

/// Game 2 deals with the ace of spades already exposed, and hides the ace of
/// diamonds directly under the five of spades. Both stay put until a move is
/// made; then auto-play takes the spade, and the diamond the move uncovers.
pub fn playing_a_move_sends_home_whatever_is_safe_test() {
  let start = game.new(2, rules.Standard)
  assert fixture.foundations(game.board(start)) == "C:0 D:0 H:0 S:0"

  let assert Ok(#(after, carried)) = game.play(start, Move(Cascade(1), Free(0)))
  assert carried == 1
  assert fixture.foundations(game.board(after)) == "C:0 D:1 H:0 S:1"
}

pub fn auto_play_can_be_turned_off_and_on_test() {
  let start = game.set_auto_play(game.new(2, rules.Standard), False)
  assert !game.auto_play_enabled(start)

  let assert Ok(#(after, _)) = game.play(start, Move(Cascade(1), Free(0)))
  assert fixture.foundations(game.board(after)) == "C:0 D:0 H:0 S:0"

  // Switching it back on catches up on what it would have done.
  let caught_up = game.set_auto_play(after, True)
  assert game.auto_play_enabled(caught_up)
  assert fixture.foundations(game.board(caught_up)) == "C:0 D:1 H:0 S:1"
}

pub fn undo_and_redo_retrace_the_game_test() {
  let start = game.new(1, rules.Standard)
  let assert Ok(#(one, _)) = game.play(start, Move(Cascade(0), Free(0)))
  assert game.moves(one) == 1
  assert game.can_undo(one)
  assert !game.can_redo(one)

  let assert Ok(back) = game.undo(one)
  assert game.moves(back) == 0
  assert fixture.columns(game.board(back)) == fixture.columns(game.board(start))
  assert fixture.cells(game.board(back)) == [".", ".", ".", "."]
  assert game.can_redo(back)

  let assert Ok(forward) = game.redo(back)
  assert game.moves(forward) == 1
  assert fixture.columns(game.board(forward))
    == fixture.columns(game.board(one))
  assert fixture.cells(game.board(forward)) == ["6S", ".", ".", "."]
}

pub fn undo_stops_at_the_deal_test() {
  assert game.undo(game.new(1, rules.Standard)) == Error(Nil)
  assert game.redo(game.new(1, rules.Standard)) == Error(Nil)
}

/// Taking a different turn abandons the branch that was undone.
pub fn a_new_move_discards_the_redo_trail_test() {
  let assert Ok(#(one, _)) =
    game.play(game.new(1, rules.Standard), Move(Cascade(0), Free(0)))
  let assert Ok(back) = game.undo(one)
  assert game.can_redo(back)

  let assert Ok(#(elsewhere, _)) = game.play(back, Move(Cascade(1), Free(0)))
  assert !game.can_redo(elsewhere)
  assert fixture.cells(game.board(elsewhere)) == ["9C", ".", ".", "."]
}

pub fn a_refused_move_leaves_the_game_alone_test() {
  let start = game.new(1, rules.Standard)
  assert game.play(start, Move(Cascade(0), Cascade(1)))
    == Error(CascadeNeedsNextRankDown)
  assert game.moves(start) == 0
  assert !game.can_undo(start)
}

/// Played all the way through, a game knows it has been won. The move list
/// comes from the test solver; the point here is that `game` drives the same
/// rules to the same end.
pub fn a_game_played_to_the_end_reports_that_it_is_won_test() {
  let assert Ok(dealt) = board.new(deck.deal(1))
  let assert solver.Solved(moves, _) =
    solver.solve(rules.Standard, dealt, 20_000)

  let finished =
    list.fold(moves, game.new(1, rules.Standard), fn(state, entry) {
      let #(move, _) = entry
      let assert Ok(#(next, _)) = game.play(state, move)
      next
    })

  assert game.status(finished) == game.Won
  assert game.moves(finished) == list.length(moves)
  assert board.card_count(game.board(finished)) == 52
  assert fixture.foundations(game.board(finished)) == "C:13 D:13 H:13 S:13"
}
