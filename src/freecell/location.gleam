//// The places a card can sit on a FreeCell board.

import freecell/card.{type Suit}

/// Cascades are indexed 0-7 and free cells 0-3. Foundations are keyed by suit
/// rather than by slot, because a suit's pile is the only one it can ever go
/// on — there is no meaningful choice for the player to make there.
pub type Location {
  Cascade(index: Int)
  Free(index: Int)
  Foundation(suit: Suit)
}
