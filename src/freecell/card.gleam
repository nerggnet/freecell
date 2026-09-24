//// Cards, suits and ranks. Pure, no I/O.

import gleam/int
import gleam/string

pub type Suit {
  Clubs
  Diamonds
  Hearts
  Spades
}

pub type Color {
  Black
  Red
}

/// A playing card. `rank` runs 1 (ace) to 13 (king); the rules code compares
/// and increments it constantly, so it stays a plain Int rather than a type
/// that would need unwrapping at every call site.
pub type Card {
  Card(rank: Int, suit: Suit)
}

pub const ace = 1

pub const king = 13

/// The four suits in the order the Microsoft deal numbers them.
pub fn suits() -> List(Suit) {
  [Clubs, Diamonds, Hearts, Spades]
}

/// Ace through king, ascending.
pub fn ranks() -> List(Int) {
  // int.range is a fold with an exclusive upper bound, so counting down and
  // prepending is what produces an ascending list without a reverse.
  int.range(from: king, to: ace - 1, with: [], run: fn(acc, rank) {
    [rank, ..acc]
  })
}

pub fn color(suit: Suit) -> Color {
  case suit {
    Clubs | Spades -> Black
    Diamonds | Hearts -> Red
  }
}

/// True when two cards may stack on a cascade as far as colour goes.
pub fn alternates(a: Card, b: Card) -> Bool {
  color(a.suit) != color(b.suit)
}

pub fn suit_symbol(suit: Suit) -> String {
  case suit {
    Clubs -> "♣"
    Diamonds -> "♦"
    Hearts -> "♥"
    Spades -> "♠"
  }
}

pub fn suit_letter(suit: Suit) -> String {
  case suit {
    Clubs -> "C"
    Diamonds -> "D"
    Hearts -> "H"
    Spades -> "S"
  }
}

/// Always one character wide, so cascades line up without padding. Ten is "T"
/// for that reason.
pub fn rank_label(rank: Int) -> String {
  case rank {
    1 -> "A"
    10 -> "T"
    11 -> "J"
    12 -> "Q"
    13 -> "K"
    other -> int.to_string(other)
  }
}

/// Two-character ASCII form such as "AS" or "TD", used by tests and fixtures.
pub fn to_code(card: Card) -> String {
  rank_label(card.rank) <> suit_letter(card.suit)
}

/// Display form such as "A♠". Two graphemes wide but four bytes: pad columns
/// by `string.length`, never by byte size.
pub fn to_string(card: Card) -> String {
  rank_label(card.rank) <> suit_symbol(card.suit)
}

pub fn from_code(code: String) -> Result(Card, Nil) {
  case string.to_graphemes(string.uppercase(code)) {
    [rank_char, suit_char] -> {
      case parse_rank(rank_char), parse_suit(suit_char) {
        Ok(rank), Ok(suit) -> Ok(Card(rank, suit))
        _, _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn parse_rank(char: String) -> Result(Int, Nil) {
  case char {
    "A" -> Ok(1)
    "T" -> Ok(10)
    "J" -> Ok(11)
    "Q" -> Ok(12)
    "K" -> Ok(13)
    other ->
      case int.parse(other) {
        Ok(rank) if rank >= 2 && rank <= 9 -> Ok(rank)
        _ -> Error(Nil)
      }
  }
}

fn parse_suit(char: String) -> Result(Suit, Nil) {
  case char {
    "C" -> Ok(Clubs)
    "D" -> Ok(Diamonds)
    "H" -> Ok(Hearts)
    "S" -> Ok(Spades)
    _ -> Error(Nil)
  }
}
