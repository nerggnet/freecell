import fixture
import freecell/board
import freecell/deck
import freecell/location.{type Location, Cascade, Foundation, Free}
import freecell/render
import freecell/rules
import freecell/solver
import freecell/stats
import freecell/tui/app
import freecell/tui/key.{
  type Key, Backspace, Char, Ctrl, Down, Enter, Escape, Space, Up,
}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

fn start() -> app.State {
  app.new(1, 0, render.plain(), stats.empty(), 0, rules.Standard)
}

/// Feed keys in, expecting the game to keep running.
fn press(state: app.State, keys: List(Key)) -> app.State {
  list.fold(keys, state, fn(current, pressed) {
    let assert app.Continue(next) = app.update(current, app.KeyPress(pressed))
      as { "unexpected quit on " <> string.inspect(pressed) }
    next
  })
}

fn message(state: app.State) -> String {
  app.view(state).message
}

// --- Picking cards up ------------------------------------------------------

/// Game 1 leaves the six of spades exposed at the foot of column 1.
pub fn a_column_key_picks_the_column_up_test() {
  let picked = press(start(), [Char("1")])
  assert app.view(picked).selection == Some(render.Selection(Cascade(0), 1))
  assert message(picked) == ""
}

pub fn pressing_the_same_place_twice_puts_it_back_test() {
  let put_back = press(start(), [Char("1"), Char("1")])
  assert app.view(put_back).selection == None
  assert message(put_back) == "Put back."
}

pub fn escape_and_backspace_cancel_a_selection_test() {
  assert app.view(press(start(), [Char("1"), Escape])).selection == None
  assert app.view(press(start(), [Char("1"), Backspace])).selection == None
}

pub fn an_empty_place_cannot_be_picked_up_test() {
  let nothing = press(start(), [Char("a")])
  assert app.view(nothing).selection == None
  assert message(nothing) == "Nothing to pick up there."
}

// --- Moving ----------------------------------------------------------------

pub fn a_second_key_completes_the_move_test() {
  let moved = press(start(), [Char("1"), Char("a")])
  let seen = app.view(moved)
  assert seen.selection == None
  assert seen.moves == 1
  assert fixture.cells(seen.board) == ["6S", ".", ".", "."]
}

/// A refused move explains itself and keeps hold of the card, so the player
/// can simply aim somewhere else.
pub fn a_refused_move_keeps_the_card_in_hand_test() {
  let refused = press(start(), [Char("1"), Char("2")])
  let seen = app.view(refused)
  assert seen.selection == Some(render.Selection(Cascade(0), 1))
  assert seen.moves == 0
  assert seen.message == "Cards stack one rank down."
}

pub fn space_sends_the_selection_home_test() {
  // Nothing in game 1 can go home on the first move, so this is refused —
  // but it is refused by the *foundation* rule, which is the point.
  let tried = press(start(), [Char("1"), Space])
  assert message(tried) == "The foundation wants the next rank up."
}

pub fn space_with_nothing_in_hand_says_so_test() {
  assert message(press(start(), [Space])) == "Pick a card up first."
  assert message(press(start(), [Enter])) == "Pick a card up first."
}

// --- Undo and redo ---------------------------------------------------------

pub fn undo_and_redo_are_bound_to_u_and_r_test() {
  let moved = press(start(), [Char("1"), Char("a")])
  assert app.view(moved).moves == 1

  let undone = press(moved, [Char("u")])
  assert app.view(undone).moves == 0
  assert message(undone) == "Undone."
  assert fixture.cells(app.view(undone).board) == [".", ".", ".", "."]

  let redone = press(undone, [Char("r")])
  assert app.view(redone).moves == 1
  assert message(redone) == "Redone."
}

pub fn undo_at_the_start_says_there_is_nothing_to_undo_test() {
  assert message(press(start(), [Char("u")])) == "Nothing to undo."
  assert message(press(start(), [Char("r")])) == "Nothing to redo."
}

// --- Quitting --------------------------------------------------------------

pub fn q_asks_before_quitting_test() {
  let assert app.Continue(asking) = app.update(start(), app.KeyPress(Char("q")))
  assert string.contains(app.view(asking).message, "Quit?")
  let assert app.Quit(_) = app.update(asking, app.KeyPress(Char("y")))
}

pub fn declining_the_quit_carries_on_test() {
  let assert app.Continue(asking) = app.update(start(), app.KeyPress(Char("q")))
  let assert app.Continue(staying) = app.update(asking, app.KeyPress(Char("n")))
  assert !string.contains(app.view(staying).message, "Quit?")
  // And the game is still playable afterwards.
  assert app.view(press(staying, [Char("1")])).selection
    == Some(render.Selection(Cascade(0), 1))
}

/// Ctrl-C is the one key that does not stop to ask.
pub fn ctrl_c_quits_at_once_test() {
  let assert app.Quit(_) = app.update(start(), app.KeyPress(Ctrl("c")))
}

// --- Other -----------------------------------------------------------------

pub fn n_deals_a_different_game_test() {
  let next = press(start(), [Char("n")])
  assert app.game_number(next) != 1
  assert app.view(next).moves == 0
  assert app.view(next).selection == None
}

pub fn keys_with_no_meaning_do_nothing_test() {
  let before = app.view(start())
  let after = app.view(press(start(), [Char("z"), Char("9"), Char("%")]))
  assert after.board == before.board
  assert after.selection == before.selection
  assert after.moves == before.moves
}

/// Every refusal has something to say; none may fall through to a blank.
pub fn every_refusal_has_a_message_test() {
  list.each(
    [
      rules.SameLocation,
      rules.NoSuchLocation,
      rules.EmptySource,
      rules.FoundationsAreOneWay,
      rules.FreeCellOccupied,
      rules.WrongSuitForFoundation,
      rules.FoundationNeedsNextRank,
      rules.CascadeNeedsNextRankDown,
      rules.CascadeNeedsAlternatingColour,
      rules.NotASequence,
      rules.NotEnoughRoom(3),
      rules.RunsOnlyBetweenCascades,
      rules.NoCardsToMove,
    ],
    fn(reason) {
      assert app.describe(reason) != ""
    },
  )
  assert app.describe(rules.NotEnoughRoom(1))
    == "Only 1 card can move at once — free a cell or a column."
  assert app.describe(rules.NotEnoughRoom(3))
    == "Only 3 cards can move at once — free a cell or a column."
}

// --- Help ------------------------------------------------------------------

pub fn question_mark_shows_the_keys_test() {
  let helping = press(start(), [Char("?")])
  let shown = app.screen(helping) |> string.join("\n")
  assert string.contains(shown, "pick up a column")
  assert string.contains(shown, "undo, redo")
  assert string.contains(shown, "Record")
  // The board is not on screen while the help is.
  assert !string.contains(shown, "FreeCell #1")
}

/// Any key gets you out, so nobody has to guess.
pub fn any_key_dismisses_the_help_test() {
  list.each([Char("?"), Escape, Char("z"), Space], fn(pressed) {
    let back = press(press(start(), [Char("?")]), [pressed])
    assert string.contains(string.join(app.screen(back), "\n"), "FreeCell #1")
  })
}

pub fn the_help_does_not_disturb_the_game_test() {
  let picked = press(start(), [Char("1")])
  let after = press(picked, [Char("?"), Char("?")])
  assert app.view(after).selection == app.view(picked).selection
  assert app.view(after).moves == app.view(picked).moves
}

// --- Auto-play toggle ------------------------------------------------------

pub fn p_toggles_auto_play_test() {
  let off = press(start(), [Char("p")])
  assert message(off) == "Auto-play off."
  let on = press(off, [Char("p")])
  assert message(on) == "Auto-play on."
}

/// With auto-play off the ace of spades that game 2 deals face up stays put.
pub fn auto_play_off_leaves_cards_alone_test() {
  let manual =
    app.new(2, 0, render.plain(), stats.empty(), 0, rules.Standard)
    |> fn(state) { press(state, [Char("p")]) }
  let moved = press(manual, [Char("2"), Char("a")])
  assert fixture.foundations(app.view(moved).board) == "C:0 D:0 H:0 S:0"

  let automatic = press(start_of_game_two(), [Char("2"), Char("a")])
  assert fixture.foundations(app.view(automatic).board) == "C:0 D:1 H:0 S:1"
}

fn start_of_game_two() -> app.State {
  app.new(2, 0, render.plain(), stats.empty(), 0, rules.Standard)
}

// --- Keeping score ---------------------------------------------------------

pub fn walking_away_from_an_untouched_game_is_not_a_loss_test() {
  let assert app.Quit(final) = app.update(start(), app.KeyPress(Ctrl("c")))
  assert app.record(final) == stats.empty()
}

pub fn abandoning_a_game_in_progress_counts_as_a_loss_test() {
  let played = press(start(), [Char("1"), Char("a")])
  let assert app.Quit(final) = app.update(played, app.KeyPress(Ctrl("c")))
  assert app.record(final).played == 1
  assert app.record(final).won == 0
  assert app.record(final).streak == 0
}

pub fn dealing_a_new_game_counts_the_one_left_behind_test() {
  let dealt = press(start(), [Char("1"), Char("a"), Char("n")])
  assert app.record(dealt).played == 1
  assert app.record(dealt).won == 0
  assert app.game_number(dealt) != 1
}

/// A game is counted once, however many times it is left.
pub fn a_game_is_not_counted_twice_test() {
  let played = press(start(), [Char("1"), Char("a"), Char("n")])
  let assert app.Quit(final) = app.update(played, app.KeyPress(Ctrl("c")))
  assert app.record(final).played == 1
}

/// Played to the end through the keyboard rather than through `game`, so the
/// whole interface — selection, destination keys, auto-play, win detection and
/// the record — is exercised the way a person would.
pub fn winning_a_game_is_recorded_test() {
  let assert Ok(dealt) = board.new(deck.deal(1))
  let assert solver.Solved(moves, _) =
    solver.solve(rules.Standard, dealt, 20_000)

  let keystrokes =
    list.flat_map(moves, fn(entry) {
      let #(move, _) = entry
      [key_for(move.from), key_for(move.to)]
    })

  let finished = press(start(), keystrokes)
  assert string.contains(string.join(app.screen(finished), "\n"), "You win")
  assert app.record(finished)
    == stats.Stats(played: 1, won: 1, streak: 1, best_streak: 1)
}

fn key_for(place: Location) -> Key {
  case place {
    Cascade(index) -> Char(int.to_string(index + 1))
    Free(0) -> Char("a")
    Free(1) -> Char("s")
    Free(2) -> Char("d")
    Free(_) -> Char("f")
    // Space sends whatever is in hand to its own suit's foundation.
    Foundation(_) -> Space
  }
}

// --- Hints and finishing ---------------------------------------------------

/// `update` does not search; it asks to be searched for, and the loop obliges.
/// That is what keeps it pure and the game responsive while thinking.
pub fn h_asks_for_a_search_rather_than_running_one_test() {
  let assert app.Think(thinking, _generation, _, asked_about, budget) =
    app.update(start(), app.KeyPress(Char("h")))
  assert budget > 0
  assert fixture.columns(asked_about)
    == fixture.columns(app.view(start()).board)
  assert string.contains(app.view(thinking).message, "Looking for a move")
}

pub fn a_hint_names_a_move_test() {
  let assert app.Think(thinking, generation, _, asked_about, budget) =
    app.update(start(), app.KeyPress(Char("h")))
  let assert app.Continue(hinted) =
    app.update(
      thinking,
      app.Searched(
        generation,
        solver.solve(rules.Standard, asked_about, budget),
      ),
    )

  let said = app.view(hinted).message
  assert string.starts_with(said, "Try ")
  assert string.contains(said, " to ")
}

/// A first pass that finds nothing does not refuse; it looks harder. Almost
/// every deal the quick look gives up on yields to a longer one, so refusing
/// there would be telling the player something untrue.
pub fn a_fruitless_first_look_escalates_test() {
  let assert app.Think(thinking, generation, _, _, first) =
    app.update(start(), app.KeyPress(Char("h")))

  let assert app.Think(harder, _, _, _, second) =
    app.update(thinking, app.Searched(generation, solver.Unsolved(99, True)))
  assert second > first
  assert string.contains(app.view(harder).message, "looking harder")
}

/// Only once the longer look has also come back empty is the player told there
/// is nothing to find.
pub fn a_hint_admits_defeat_after_looking_harder_test() {
  let assert app.Continue(answered) = exhaust(start(), Char("h"))
  assert string.contains(app.view(answered).message, "No way through")
}

/// Drive a search through every stage, answering each with nothing found.
fn exhaust(state: app.State, key: Key) -> app.Step {
  case app.update(state, app.KeyPress(key)) {
    app.Think(thinking, generation, _, _, _) ->
      keep_failing(thinking, generation)
    other -> other
  }
}

fn keep_failing(state: app.State, generation: Int) -> app.Step {
  case app.update(state, app.Searched(generation, solver.Unsolved(99, True))) {
    app.Think(again, next_generation, _, _, _) ->
      keep_failing(again, next_generation)
    other -> other
  }
}

/// The board can move on while a search runs. Its answer is then about a
/// position that no longer exists, and must be thrown away.
pub fn an_answer_about_a_stale_board_is_dropped_test() {
  let assert app.Think(thinking, generation, _, _, _) =
    app.update(start(), app.KeyPress(Char("h")))
  let moved = press(thinking, [Char("1"), Char("a")])

  let assert app.Continue(after) =
    app.update(moved, app.Searched(generation, solver.Unsolved(99, True)))
  assert !string.contains(app.view(after).message, "No way through")
  assert app.view(after).moves == app.view(moved).moves
}

pub fn asking_twice_does_not_start_two_searches_test() {
  let assert app.Think(thinking, _, _, _, _) =
    app.update(start(), app.KeyPress(Char("h")))
  let assert app.Continue(again) = app.update(thinking, app.KeyPress(Char("h")))
  assert app.view(again).message == "Still thinking."
}

/// The real solver, on a real deal, played through to a win by the game.
pub fn finishing_plays_the_game_out_and_records_the_win_test() {
  let assert app.Think(thinking, generation, _, asked_about, budget) =
    app.update(start(), app.KeyPress(Char("!")))
  let assert app.Continue(finished) =
    app.update(
      thinking,
      app.Searched(
        generation,
        solver.solve(rules.Standard, asked_about, budget),
      ),
    )

  assert app.view(finished).message == "Finished."
  assert string.contains(string.join(app.screen(finished), "\n"), "You win")
  assert app.record(finished)
    == stats.Stats(played: 1, won: 1, streak: 1, best_streak: 1)
}

pub fn finishing_admits_when_it_cannot_test() {
  let assert app.Continue(answered) = exhaust(start(), Char("!"))
  assert string.contains(app.view(answered).message, "could not find")
}

/// The board can still move on mid-escalation, and the longer look's answer
/// has to be dropped just like the first one's.
pub fn a_stale_answer_from_the_longer_look_is_dropped_test() {
  let assert app.Think(thinking, generation, _, _, _) =
    app.update(start(), app.KeyPress(Char("h")))
  let assert app.Think(harder, second_generation, _, _, _) =
    app.update(thinking, app.Searched(generation, solver.Unsolved(99, True)))

  let moved = press(harder, [Char("1"), Char("a")])
  let assert app.Continue(after) =
    app.update(
      moved,
      app.Searched(second_generation, solver.Unsolved(99, True)),
    )
  assert !string.contains(app.view(after).message, "No way through")
}

/// A first look that succeeds answers straight away rather than grinding on.
pub fn a_successful_first_look_does_not_escalate_test() {
  let assert app.Think(thinking, generation, _, asked_about, budget) =
    app.update(start(), app.KeyPress(Char("h")))
  let assert app.Continue(hinted) =
    app.update(
      thinking,
      app.Searched(
        generation,
        solver.solve(rules.Standard, asked_about, budget),
      ),
    )
  assert string.starts_with(app.view(hinted).message, "Try ")
}

pub fn the_help_mentions_hints_test() {
  let shown = app.screen(press(start(), [Char("?")])) |> string.join("\n")
  assert string.contains(shown, "suggest a move")
  assert string.contains(shown, "finish the game")
}

// --- Taking part of a run --------------------------------------------------

/// Game 251 deals Q♠ J♥ T♣ at the foot of column 3: a run of three.
fn with_a_run() -> app.State {
  app.new(251, 0, render.plain(), stats.empty(), 0, rules.Standard)
}

pub fn a_column_is_picked_up_run_and_all_test() {
  let picked = press(with_a_run(), [Char("3")])
  assert app.view(picked).selection == Some(render.Selection(Cascade(2), 3))
}

pub fn the_arrows_take_more_or_fewer_cards_test() {
  let picked = press(with_a_run(), [Char("3")])

  let fewer = press(picked, [Down])
  assert app.view(fewer).selection == Some(render.Selection(Cascade(2), 2))
  assert message(fewer) == "Holding 2 of 3."

  // It will not go below one, however hard you press.
  let fewest = press(fewer, [Down, Down, Down])
  assert app.view(fewest).selection == Some(render.Selection(Cascade(2), 1))

  // Nor above what is actually there.
  let more = press(fewest, [Up, Up, Up, Up])
  assert app.view(more).selection == Some(render.Selection(Cascade(2), 3))
}

/// Left alone, a move carries as many cards as will go — one, into a free
/// cell. Say "three" explicitly and it is refused instead of quietly doing
/// something else.
pub fn an_explicit_count_is_honoured_test() {
  let by_default = press(with_a_run(), [Char("3"), Char("a")])
  assert app.view(by_default).moves == 1
  assert fixture.cells(app.view(by_default).board) == ["TC", ".", ".", "."]

  let insisting = press(with_a_run(), [Char("3"), Up, Char("a")])
  assert app.view(insisting).moves == 0
  assert message(insisting) == "Only one card can go there."
}

pub fn picking_something_else_up_forgets_the_count_test() {
  let adjusted = press(with_a_run(), [Char("3"), Down])
  assert app.view(adjusted).selection == Some(render.Selection(Cascade(2), 2))

  let elsewhere = press(adjusted, [Escape, Char("3")])
  assert app.view(elsewhere).selection == Some(render.Selection(Cascade(2), 3))
}

pub fn the_arrows_need_something_in_hand_test() {
  assert message(press(with_a_run(), [Up])) == "Pick a card up first."
  assert message(press(with_a_run(), [Down])) == "Pick a card up first."
}

pub fn a_single_card_column_says_there_is_no_more_to_take_test() {
  let picked = press(start(), [Char("1"), Up])
  assert message(picked) == "Only one card can travel from there."
  assert app.view(picked).selection == Some(render.Selection(Cascade(0), 1))
}

// --- The clock and starting over -------------------------------------------

/// Time is told to the game rather than read by it, which is what lets
/// `update` stay a pure function of its inputs.
pub fn the_clock_counts_from_the_deal_test() {
  let fresh = start()
  assert app.view(fresh).elapsed == 0
  // Ninety seconds later, in microseconds.
  assert app.view(app.at(fresh, 90_000_000)).elapsed == 90
}

pub fn restart_deals_the_same_game_again_test() {
  let played = press(start(), [Char("1"), Char("a")])
  assert app.view(played).moves == 1

  let again = press(played, [Char("R")])
  assert app.game_number(again) == 1
  assert app.view(again).moves == 0
  assert fixture.columns(app.view(again).board)
    == fixture.columns(app.view(start()).board)
  assert message(again) == "Dealt again."
}

pub fn restart_puts_the_clock_back_test() {
  let later = app.at(press(start(), [Char("1"), Char("a")]), 60_000_000)
  assert app.view(later).elapsed == 60
  assert app.view(press(later, [Char("R")])).elapsed == 0
}

/// Restarting is giving up on the deal. Otherwise a streak could be kept alive
/// indefinitely by starting over whenever one turned awkward.
pub fn restart_counts_as_a_game_given_up_test() {
  let again = press(start(), [Char("1"), Char("a"), Char("R")])
  assert app.record(again).played == 1
  assert app.record(again).won == 0
  assert app.record(again).streak == 0
}

pub fn restarting_an_untouched_deal_costs_nothing_test() {
  assert app.record(press(start(), [Char("R")])) == stats.empty()
}

// --- Relaxed rules ---------------------------------------------------------

fn casual() -> app.State {
  app.new(1, 0, render.plain(), stats.empty(), 0, rules.Relaxed)
}

pub fn m_switches_between_the_rules_test() {
  assert app.mode(start()) == rules.Standard

  let relaxed = press(start(), [Char("m")])
  assert app.mode(relaxed) == rules.Relaxed
  assert message(relaxed) == "Relaxed rules. This game will not be recorded."

  let back = press(relaxed, [Char("m")])
  assert app.mode(back) == rules.Standard
  assert message(back) == "Standard rules. This game is still not recorded."
}

/// There is no carrying limit to report under the relaxed rules, so the header
/// says which rules are in force instead of a number.
pub fn the_header_says_when_the_rules_are_relaxed_test() {
  assert app.view(start()).carry == Some(5)
  assert app.view(casual()).carry == None
  assert app.view(press(start(), [Char("m")])).carry == None
}

/// A relaxed game is left out of the record, win or lose. Counting both kinds
/// together would make the record mean two things at once.
pub fn relaxed_games_are_not_recorded_test() {
  let played = press(casual(), [Char("1"), Char("a")])
  assert app.view(played).moves == 1

  let assert app.Quit(final) = app.update(played, app.KeyPress(Ctrl("c")))
  assert app.record(final) == stats.empty()
}

/// Switching to relaxed part-way through taints the game, and switching back
/// does not wash it out.
pub fn a_game_touched_by_relaxed_rules_stays_unrecorded_test() {
  let played = press(start(), [Char("1"), Char("a"), Char("m"), Char("m")])
  let assert app.Quit(final) = app.update(played, app.KeyPress(Ctrl("c")))
  assert app.record(final) == stats.empty()
}

pub fn a_new_deal_keeps_the_rules_in_force_test() {
  let dealt = press(press(start(), [Char("m")]), [Char("n")])
  assert app.mode(dealt) == rules.Relaxed
  assert app.view(dealt).carry == None
}

/// Going back to the standard rules and dealing again starts a game that
/// counts once more.
pub fn a_fresh_standard_deal_counts_again_test() {
  let back = press(start(), [Char("1"), Char("a"), Char("m"), Char("m")])
  let dealt = press(back, [Char("n")])
  assert app.mode(dealt) == rules.Standard

  let played = press(dealt, [Char("1"), Char("a")])
  let assert app.Quit(final) = app.update(played, app.KeyPress(Ctrl("c")))
  assert app.record(final).played == 1
}

/// A new deal starts its own clock. Only `R` was covered before, and `n` had
/// quietly never reset it.
pub fn a_new_deal_starts_the_clock_again_test() {
  let later = app.at(press(start(), [Char("1"), Char("a")]), 90_000_000)
  assert app.view(later).elapsed == 90
  assert app.view(press(later, [Char("n")])).elapsed == 0
}
