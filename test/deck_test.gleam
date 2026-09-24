import freecell/card
import freecell/deck
import gleam/list
import gleam/string

fn codes(cascade: List(card.Card)) -> String {
  cascade |> list.map(card.to_code) |> string.join(" ")
}

fn layout(game_number: Int) -> List(String) {
  deck.deal(game_number) |> list.map(codes)
}

/// The published layout for Microsoft FreeCell game #1, read down each column.
/// This fixture comes from outside our code, so it checks the algorithm rather
/// than just restating it.
pub fn deal_one_matches_published_layout_test() {
  assert layout(1)
    == [
      "JD KD 2S 4C 3S 6D 6S", "2D KC KS 5C TD 8S 9C", "9H 9S 9D TS 4S 8D 2H",
      "JC 5S QD QH TH QS 6H", "5D AD JS 4H 8H 6C", "7H QC AS AC 2C 3D",
      "7C KH AH 4D JH 8C", "5H 3H 3C 7S 7D TC",
    ]
}

pub fn ordered_deck_holds_fifty_two_distinct_cards_test() {
  let all = deck.ordered() |> list.map(card.to_code)
  assert list.length(all) == 52
  assert list.length(list.unique(all)) == 52
}

pub fn every_deal_is_a_permutation_of_the_deck_test() {
  let sorted_deck =
    deck.ordered() |> list.map(card.to_code) |> list.sort(string.compare)

  list.each([1, 2, 617, 11_982, 32_000], fn(game_number) {
    let dealt =
      deck.deal(game_number)
      |> list.flatten
      |> list.map(card.to_code)
      |> list.sort(string.compare)
    assert dealt == sorted_deck
  })
}

pub fn cascades_are_seven_seven_seven_seven_six_six_six_six_test() {
  assert deck.deal(617) |> list.map(list.length) == [7, 7, 7, 7, 6, 6, 6, 6]
}

pub fn different_game_numbers_deal_differently_test() {
  assert layout(1) != layout(2)
  assert layout(617) != layout(11_982)
}

/// The same number must always give the same game, or the whole point of
/// numbered deals evaporates.
pub fn deals_are_reproducible_test() {
  assert layout(617) == layout(617)
}
