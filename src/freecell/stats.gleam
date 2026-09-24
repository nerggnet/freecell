//// A running record of games played, kept between sessions.
////
//// Pure: reading and writing the file happens in `freecell`. Parsing is
//// deliberately forgiving — a missing, truncated or hand-edited file yields
//// zeroes rather than stopping anyone from playing a card game.

import gleam/int
import gleam/list
import gleam/string

pub type Stats {
  Stats(played: Int, won: Int, streak: Int, best_streak: Int)
}

pub fn empty() -> Stats {
  Stats(played: 0, won: 0, streak: 0, best_streak: 0)
}

pub fn record_win(stats: Stats) -> Stats {
  let streak = stats.streak + 1
  Stats(
    played: stats.played + 1,
    won: stats.won + 1,
    streak: streak,
    best_streak: int.max(streak, stats.best_streak),
  )
}

/// Abandoning or losing a game breaks the streak but still counts as played.
pub fn record_loss(stats: Stats) -> Stats {
  Stats(..stats, played: stats.played + 1, streak: 0)
}

pub fn win_rate(stats: Stats) -> Int {
  case stats.played {
    0 -> 0
    played -> stats.won * 100 / played
  }
}

pub fn summary(stats: Stats) -> String {
  case stats.played {
    0 -> "no games yet"
    _ ->
      int.to_string(stats.played)
      <> " played · "
      <> int.to_string(stats.won)
      <> " won ("
      <> int.to_string(win_rate(stats))
      <> "%) · streak "
      <> int.to_string(stats.streak)
      <> " · best "
      <> int.to_string(stats.best_streak)
  }
}

pub fn to_text(stats: Stats) -> String {
  [
    "played=" <> int.to_string(stats.played),
    "won=" <> int.to_string(stats.won),
    "streak=" <> int.to_string(stats.streak),
    "best_streak=" <> int.to_string(stats.best_streak),
  ]
  |> string.join("\n")
  <> "\n"
}

pub fn parse(text: String) -> Stats {
  let fields = text |> string.split("\n") |> list.filter_map(field)
  Stats(
    played: value(fields, "played"),
    won: value(fields, "won"),
    streak: value(fields, "streak"),
    best_streak: value(fields, "best_streak"),
  )
}

fn field(line: String) -> Result(#(String, Int), Nil) {
  case string.split_once(line, "=") {
    Error(Nil) -> Error(Nil)
    Ok(#(name, raw)) ->
      case int.parse(string.trim(raw)) {
        Ok(number) if number >= 0 -> Ok(#(string.trim(name), number))
        _ -> Error(Nil)
      }
  }
}

fn value(fields: List(#(String, Int)), name: String) -> Int {
  fields
  |> list.filter(fn(entry) { entry.0 == name })
  |> list.map(fn(entry) { entry.1 })
  |> list.first
  |> fn(found) {
    case found {
      Ok(number) -> number
      Error(Nil) -> 0
    }
  }
}
