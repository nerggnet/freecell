//// Deterministic deals, compatible with the Microsoft FreeCell game numbers.
////
//// Reproducing that exact algorithm is worth the fuss twice over: players can
//// ask for a deal they know, and the published layouts give us test fixtures
//// with an authority outside our own code.

import freecell/card.{type Card, Card}
import gleam/int
import gleam/list

/// The 52 cards in the order the deal algorithm indexes them: position i holds
/// rank i / 4 + 1 in suit i % 4 (clubs, diamonds, hearts, spades).
pub fn ordered() -> List(Card) {
  card.ranks()
  |> list.flat_map(fn(rank) {
    list.map(card.suits(), fn(suit) { Card(rank, suit) })
  })
}

/// Deal a game into its eight cascades.
///
/// Each cascade is ordered as printed: first element is the buried card at the
/// top of the column, last element is the exposed card players can move.
/// Cascades 1-4 get seven cards, 5-8 get six.
pub fn deal(game_number: Int) -> List(List(Card)) {
  let dealt = deal_order(ordered(), game_number, [])
  int.range(from: 7, to: -1, with: [], run: fn(columns, index) {
    [column(dealt, index), ..columns]
  })
}

/// Cards in the order they leave the deck. They fill the cascades left to
/// right, one row at a time.
fn deal_order(
  remaining: List(Card),
  seed: Int,
  taken: List(Card),
) -> List(Card) {
  case remaining {
    [] -> list.reverse(taken)
    _ -> {
      let #(random, next_seed) = next_random(seed)
      let index = random % list.length(remaining)
      let assert Ok(#(chosen, rest)) = pluck(remaining, index)
        as "index is taken modulo the length, so it is always in range"
      deal_order(rest, next_seed, [chosen, ..taken])
    }
  }
}

/// Take the card at `index`, moving the *last* card into the hole it leaves.
///
/// That swap-and-shrink is load-bearing. Closing the gap the obvious way, by
/// joining the cards either side, would leave the remaining deck in a
/// different order and every deal number would name the wrong game.
fn pluck(cards: List(Card), index: Int) -> Result(#(Card, List(Card)), Nil) {
  let #(before, rest) = list.split(cards, index)
  case rest {
    [] -> Error(Nil)
    [chosen, ..after] -> {
      let filled = case list.reverse(after) {
        [] -> []
        [last, ..middle] -> [last, ..list.reverse(middle)]
      }
      Ok(#(chosen, list.append(before, filled)))
    }
  }
}

/// The linear congruential generator shipped with Microsoft's C runtime.
/// Returns a value in 0..32767 alongside the next seed.
fn next_random(seed: Int) -> #(Int, Int) {
  let next = { seed * 214_013 + 2_531_011 } % 0x80000000
  #(int.bitwise_shift_right(next, 16), next)
}

fn column(dealt: List(Card), index: Int) -> List(Card) {
  dealt
  |> list.index_map(fn(card, position) { #(position % 8, card) })
  |> list.filter_map(fn(entry) {
    case entry.0 == index {
      True -> Ok(entry.1)
      False -> Error(Nil)
    }
  })
}

/// A pseudo-random game number in the Microsoft range, and the seed that
/// follows it. Reuses the deal generator so there is only one of these.
pub fn next_game_number(seed: Int) -> #(Int, Int) {
  let #(random, next) = next_random(seed)
  #(random % 32_000 + 1, next)
}
