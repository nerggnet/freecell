import fixture
import freecell/board.{type Board}
import freecell/card.{Card, Diamonds, Hearts}
import freecell/deck
import freecell/location.{Cascade, Foundation, Free}
import freecell/rules.{
  type Illegal, type Move, CascadeNeedsAlternatingColour,
  CascadeNeedsNextRankDown, EmptySource, FoundationNeedsNextRank,
  FoundationsAreOneWay, FreeCellOccupied, Move, NoSuchLocation, SameLocation,
  WrongSuitForFoundation,
}
import gleam/list

/// A board contrived so that every rule has something to bite on:
///
///   0: K♠   1: Q♥   2: Q♠   3: A♦   4: —   5: 2♦   6: T♣ 9♥   7: 3♣
///   free cells: 5♥ in the first, the rest empty; foundations all empty
fn scenario() -> Board {
  let base =
    fixture.board_from(["KS", "QH", "QS", "AD", "", "2D", "TC 9H", "3C"])
  let assert Ok(with_cell) = board.place(base, Free(0), Card(5, Hearts))
  with_cell
}

type Case {
  Case(description: String, move: Move, expect: Result(Nil, Illegal))
}

fn check(cases: List(Case)) -> Nil {
  list.each(cases, fn(case_) {
    assert rules.legal(scenario(), case_.move) == case_.expect
      as case_.description
  })
}

pub fn cascade_stacking_test() {
  check([
    Case("red queen onto a black king", Move(Cascade(1), Cascade(0)), Ok(Nil)),
    Case(
      "black queen onto a black king",
      Move(Cascade(2), Cascade(0)),
      Error(CascadeNeedsAlternatingColour),
    ),
    Case(
      "a nine is not one below a king",
      Move(Cascade(6), Cascade(0)),
      Error(CascadeNeedsNextRankDown),
    ),
    Case(
      "a five from a free cell is not one below a king",
      Move(Free(0), Cascade(0)),
      Error(CascadeNeedsNextRankDown),
    ),
    Case(
      "two of diamonds onto three of clubs",
      Move(Cascade(5), Cascade(7)),
      Ok(Nil),
    ),
    Case(
      "three of clubs onto two of diamonds is upside down",
      Move(Cascade(7), Cascade(5)),
      Error(CascadeNeedsNextRankDown),
    ),
  ])
}

pub fn empty_cascades_accept_anything_test() {
  check([
    Case("a queen into the gap", Move(Cascade(1), Cascade(4)), Ok(Nil)),
    Case("a king into the gap", Move(Cascade(0), Cascade(4)), Ok(Nil)),
    Case(
      "a card from a free cell into the gap",
      Move(Free(0), Cascade(4)),
      Ok(Nil),
    ),
  ])
}

pub fn foundation_rules_test() {
  check([
    Case(
      "an ace opens its foundation",
      Move(Cascade(3), Foundation(Diamonds)),
      Ok(Nil),
    ),
    Case(
      "a two cannot go before its ace",
      Move(Cascade(5), Foundation(Diamonds)),
      Error(FoundationNeedsNextRank),
    ),
    Case(
      "a diamond does not belong on hearts",
      Move(Cascade(3), Foundation(Hearts)),
      Error(WrongSuitForFoundation),
    ),
    Case(
      "nothing comes back off a foundation",
      Move(Foundation(Diamonds), Cascade(0)),
      Error(FoundationsAreOneWay),
    ),
  ])
}

pub fn free_cell_rules_test() {
  check([
    Case("an empty cell takes a card", Move(Cascade(1), Free(1)), Ok(Nil)),
    Case(
      "an occupied cell takes nothing",
      Move(Cascade(1), Free(0)),
      Error(FreeCellOccupied),
    ),
    Case(
      "an empty cell has nothing to give",
      Move(Free(1), Cascade(0)),
      Error(EmptySource),
    ),
  ])
}

pub fn malformed_moves_test() {
  check([
    Case(
      "an empty cascade has nothing to give",
      Move(Cascade(4), Cascade(0)),
      Error(EmptySource),
    ),
    Case(
      "a card cannot move to where it already is",
      Move(Cascade(0), Cascade(0)),
      Error(SameLocation),
    ),
    Case(
      "there is no ninth cascade to take from",
      Move(Cascade(8), Cascade(0)),
      Error(NoSuchLocation),
    ),
    Case(
      "there is no ninth cascade to move to",
      Move(Cascade(0), Cascade(8)),
      Error(NoSuchLocation),
    ),
    Case(
      "there is no fifth free cell",
      Move(Cascade(0), Free(4)),
      Error(NoSuchLocation),
    ),
    Case(
      "negative indices are not locations",
      Move(Cascade(-1), Cascade(0)),
      Error(NoSuchLocation),
    ),
  ])
}

pub fn applying_a_move_updates_both_ends_test() {
  let assert Ok(after) = rules.apply(scenario(), Move(Cascade(1), Cascade(0)))
  assert fixture.columns(after)
    == ["KS QH", "", "QS", "AD", "", "2D", "TC 9H", "3C"]
  assert fixture.cells(after) == ["5H", ".", ".", "."]
}

/// The two of diamonds is refused until its ace is home, then accepted.
pub fn foundations_build_up_in_order_test() {
  let assert Ok(after_ace) =
    rules.apply(scenario(), Move(Cascade(3), Foundation(Diamonds)))
  assert fixture.foundations(after_ace) == "C:0 D:1 H:0 S:0"

  let assert Ok(after_two) =
    rules.apply(after_ace, Move(Cascade(5), Foundation(Diamonds)))
  assert fixture.foundations(after_two) == "C:0 D:2 H:0 S:0"
  assert fixture.columns(after_two)
    == ["KS", "QH", "QS", "", "", "", "TC 9H", "3C"]
}

pub fn can_stack_matches_the_cascade_rule_test() {
  assert rules.can_stack(Card(12, Hearts), Card(13, card.Spades))
  assert !rules.can_stack(Card(12, card.Spades), Card(13, card.Spades))
  assert !rules.can_stack(Card(11, Hearts), Card(13, card.Spades))
}

pub fn legal_moves_are_all_actually_legal_test() {
  let assert Ok(dealt) = board.new(deck.deal(1))
  let moves = rules.legal_moves(dealt)
  assert moves != []
  list.each(moves, fn(move) {
    let assert Ok(_) = rules.apply(dealt, move)
  })
}

pub fn legal_moves_includes_a_known_move_and_excludes_a_known_non_move_test() {
  let moves = rules.legal_moves(scenario())
  assert list.contains(moves, Move(Cascade(1), Cascade(0)))
  assert list.contains(moves, Move(Cascade(3), Foundation(Diamonds)))
  assert !list.contains(moves, Move(Cascade(2), Cascade(0)))
  assert !list.contains(moves, Move(Cascade(1), Free(0)))
}

/// Whatever else a move does, the deck stays whole.
pub fn moves_never_create_or_lose_a_card_test() {
  let assert Ok(dealt) = board.new(deck.deal(617))
  list.each(rules.legal_moves(dealt), fn(move) {
    let assert Ok(after) = rules.apply(dealt, move)
    assert board.card_count(after) == 52
  })
}
