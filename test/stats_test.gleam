import freecell/stats.{Stats}

pub fn a_fresh_record_is_empty_test() {
  assert stats.empty() == Stats(played: 0, won: 0, streak: 0, best_streak: 0)
  assert stats.summary(stats.empty()) == "no games yet"
  assert stats.win_rate(stats.empty()) == 0
}

pub fn wins_extend_the_streak_test() {
  let record =
    stats.empty() |> stats.record_win |> stats.record_win |> stats.record_win
  assert record == Stats(played: 3, won: 3, streak: 3, best_streak: 3)
}

/// A loss still counts as a game played, and ends the streak without
/// disturbing the best one.
pub fn losses_end_the_streak_but_keep_the_best_test() {
  let record =
    stats.empty()
    |> stats.record_win
    |> stats.record_win
    |> stats.record_loss
    |> stats.record_win
  assert record == Stats(played: 4, won: 3, streak: 1, best_streak: 2)
}

pub fn the_win_rate_is_a_percentage_test() {
  assert stats.win_rate(Stats(played: 4, won: 1, streak: 0, best_streak: 1))
    == 25
  assert stats.win_rate(Stats(played: 3, won: 2, streak: 0, best_streak: 1))
    == 66
}

pub fn a_record_survives_a_round_trip_test() {
  let record = Stats(played: 12, won: 7, streak: 3, best_streak: 5)
  assert stats.parse(stats.to_text(record)) == record
}

/// The file is on disk where anyone can edit or truncate it. Whatever comes
/// back, the game has to start.
pub fn a_damaged_file_reads_as_zeroes_test() {
  assert stats.parse("") == stats.empty()
  assert stats.parse("garbage") == stats.empty()
  assert stats.parse("played=") == stats.empty()
  assert stats.parse("played=not a number") == stats.empty()
  assert stats.parse("played=-4") == stats.empty()
  assert stats.parse("\n\n\n") == stats.empty()
}

pub fn unknown_and_missing_fields_are_ignored_test() {
  assert stats.parse("played=5\nunheard_of=9\n")
    == Stats(played: 5, won: 0, streak: 0, best_streak: 0)
  assert stats.parse("won=2\nplayed=4\n")
    == Stats(played: 4, won: 2, streak: 0, best_streak: 0)
}

pub fn the_summary_reads_as_a_sentence_test() {
  assert stats.summary(Stats(played: 12, won: 7, streak: 3, best_streak: 5))
    == "12 played · 7 won (58%) · streak 3 · best 5"
}
