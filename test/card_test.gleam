import freecell/card.{Card, Clubs, Diamonds, Hearts, Spades}
import freecell/deck
import gleam/list
import gleam/string

pub fn colors_test() {
  assert card.color(Clubs) == card.Black
  assert card.color(Spades) == card.Black
  assert card.color(Diamonds) == card.Red
  assert card.color(Hearts) == card.Red
}

pub fn alternates_test() {
  assert card.alternates(Card(5, Hearts), Card(4, Spades))
  assert card.alternates(Card(5, Spades), Card(4, Diamonds))
  assert !card.alternates(Card(5, Hearts), Card(4, Diamonds))
  assert !card.alternates(Card(5, Clubs), Card(4, Spades))
}

pub fn ranks_run_ace_to_king_test() {
  assert card.ranks() == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
}

/// Cascades only line up if every card renders the same width.
pub fn every_card_code_is_two_characters_test() {
  list.each(deck.ordered(), fn(each) {
    assert string.length(card.to_code(each)) == 2
    assert string.length(card.to_string(each)) == 2
  })
}

pub fn code_round_trips_for_the_whole_deck_test() {
  list.each(deck.ordered(), fn(original) {
    assert card.from_code(card.to_code(original)) == Ok(original)
  })
}

pub fn codes_are_case_insensitive_test() {
  assert card.from_code("td") == Ok(Card(10, Diamonds))
  assert card.from_code("As") == Ok(Card(1, Spades))
}

pub fn bad_codes_are_rejected_test() {
  assert card.from_code("") == Error(Nil)
  assert card.from_code("A") == Error(Nil)
  assert card.from_code("1S") == Error(Nil)
  assert card.from_code("10S") == Error(Nil)
  assert card.from_code("AX") == Error(Nil)
  assert card.from_code("ZS") == Error(Nil)
}
