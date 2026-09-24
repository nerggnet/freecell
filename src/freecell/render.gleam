//// Drawing the board.
////
//// Pure: it returns lines of text and never writes anything. Colour is
//// optional and, when off, the result is plain text the tests can compare
//// against character for character.
////
//// Every slot is exactly four columns wide. Colour is applied *inside* that
//// width and never padded around, so the layout arithmetic only ever measures
//// plain text — which matters, because an escape sequence has length but no
//// width, and `A♠` has two columns but four bytes.

import freecell/board.{type Board}
import freecell/card.{type Card}
import freecell/location.{type Location, Cascade, Free}
import freecell/rules
import freecell/stats.{type Stats}
import freecell/tui/ansi
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// The keys that pick each free cell, in order.
pub const cell_keys = ["a", "s", "d", "f"]

const margin = "  "

/// Every frame is exactly this wide, so callers can centre it.
pub const board_width = 55

const slot_gap = "   "

const holder_gap = " "

pub type Suits {
  Symbols
  Letters
}

pub type Options {
  Options(colour: Bool, suits: Suits)
}

/// What the tests compare against, and what `--no-colour` produces.
pub fn plain() -> Options {
  Options(colour: False, suits: Symbols)
}

/// Everything the screen shows. Deliberately not a `Game`: the renderer has
/// no business knowing about history or undo, and tests can build a view from
/// any board without playing a game to reach it.
pub type View {
  View(
    board: Board,
    number: Int,
    moves: Int,
    selection: Option(Location),
    message: String,
  )
}

/// The whole screen, as lines. Every line is at most `board_width` wide.
pub fn frame(view: View, options: Options) -> List(String) {
  let state = view.board
  // Trailing blanks would leave debris on the screen when a line shrinks.
  list.map(
    list.flatten([
      ["", title(view), ""],
      [holder_labels(options), holders(state, view, options), ""],
      [column_labels()],
      cascades(state, view, options),
      ["", status(view), hints()],
    ]),
    string.trim_end,
  )
}

// --- Header ----------------------------------------------------------------

fn title(view: View) -> String {
  let left = "FreeCell #" <> int.to_string(view.number)
  let right = "moves " <> int.to_string(view.moves)
  margin <> spread(left, right, board_width - string.length(margin))
}

fn holder_labels(options: Options) -> String {
  let cells = list.map(cell_keys, fn(key) { centre(key, 4) })
  let piles =
    list.map(card.suits(), fn(suit) {
      centre(
        case options.suits {
          Symbols -> card.suit_symbol(suit)
          Letters -> card.suit_letter(suit)
        },
        4,
      )
    })
  two_groups(cells, piles)
}

fn holders(state: Board, view: View, options: Options) -> String {
  let cells =
    list.index_map(board.free_cells(state), fn(held, index) {
      slot(held, holder_frame(view.selection == Some(Free(index))), options)
    })
  let piles =
    list.map(card.suits(), fn(suit) {
      let top = case board.foundation(state, suit) {
        0 -> None
        rank -> Some(card.Card(rank, suit))
      }
      slot(top, Boxed, options)
    })
  two_groups(cells, piles)
}

/// Free cells on the left, foundations hard against the right edge.
fn two_groups(left: List(String), right: List(String)) -> String {
  let left_text = string.join(left, holder_gap)
  let right_text = string.join(right, holder_gap)
  margin <> spread(left_text, right_text, board_width - string.length(margin))
}

// --- Cascades --------------------------------------------------------------

fn column_labels() -> String {
  let labels =
    list.map(columns(), fn(index) { centre(int.to_string(index + 1), 4) })
  margin <> string.join(labels, slot_gap)
}

fn cascades(state: Board, view: View, options: Options) -> List(String) {
  let piles = list.map(columns(), fn(index) { display_column(state, index) })
  let depth =
    piles |> list.map(list.length) |> list.fold(0, int.max) |> int.max(1)

  list.map(rows(depth), fn(row) {
    let slots =
      list.index_map(piles, fn(pile, column) {
        let held = pile |> list.drop(row) |> list.first |> option.from_result
        let picked = case held {
          None -> False
          Some(_) ->
            row >= selection_starts_at(state, view, column, list.length(pile))
        }
        slot(held, frame_for(picked), options)
      })
    margin <> string.join(slots, slot_gap)
  })
}

fn display_column(state: Board, index: Int) -> List(Card) {
  board.cascade_display(state, index) |> unwrap_list
}

/// The display row at which this column's selection begins. A column that is
/// not selected reports a row past its own end, so nothing is marked.
fn selection_starts_at(
  state: Board,
  view: View,
  column: Int,
  depth: Int,
) -> Int {
  case view.selection {
    Some(Cascade(index)) if index == column ->
      depth - rules.run_length(state, Cascade(column))
    _ -> depth + 1
  }
}

// --- Footer ----------------------------------------------------------------

fn status(view: View) -> String {
  let text = case rules.is_won(view.board), rules.is_stuck(view.board) {
    True, _ ->
      "You win — " <> int.to_string(view.moves) <> " moves. n for a new game."
    _, True -> "No moves left. u to undo, n for a new game."
    _, _ -> view.message
  }
  margin <> text
}

fn hints() -> String {
  margin <> "1-8 col · asdf cells · space home · u undo · q quit"
}

// --- Slots -----------------------------------------------------------------

type Frame {
  /// A card sitting in a cascade.
  Bare
  /// A card in a free cell or on a foundation.
  Boxed
  /// The current selection.
  Picked
}

fn frame_for(selected: Bool) -> Frame {
  case selected {
    True -> Picked
    False -> Bare
  }
}

fn holder_frame(selected: Bool) -> Frame {
  case selected {
    True -> Picked
    False -> Boxed
  }
}

fn slot(content: Option(Card), frame: Frame, options: Options) -> String {
  let face = case content {
    None -> "  "
    Some(held) -> tint(face_of(held, options), held, options)
  }
  case frame {
    Bare -> " " <> face <> " "
    Boxed -> "[" <> face <> "]"
    Picked -> highlight(">" <> face <> "<", options)
  }
}

fn face_of(held: Card, options: Options) -> String {
  case options.suits {
    Symbols -> card.to_string(held)
    Letters -> card.to_code(held)
  }
}

fn tint(text: String, held: Card, options: Options) -> String {
  case options.colour && card.color(held.suit) == card.Red {
    True -> ansi.red(text)
    False -> text
  }
}

fn highlight(text: String, options: Options) -> String {
  case options.colour {
    True -> ansi.inverse(text)
    False -> text
  }
}

// --- Small helpers ---------------------------------------------------------

fn spread(left: String, right: String, width: Int) -> String {
  let space = width - string.length(left) - string.length(right)
  left <> string.repeat(" ", int.max(space, 1)) <> right
}

fn centre(text: String, width: Int) -> String {
  let space = width - string.length(text)
  case space <= 0 {
    True -> text
    False -> {
      let before = space / 2
      string.repeat(" ", before) <> text <> string.repeat(" ", space - before)
    }
  }
}

fn columns() -> List(Int) {
  indices(board.cascade_count)
}

fn rows(depth: Int) -> List(Int) {
  indices(depth)
}

fn indices(count: Int) -> List(Int) {
  int.range(from: count - 1, to: -1, with: [], run: fn(acc, index) {
    [index, ..acc]
  })
}

fn unwrap_list(result: Result(List(a), Nil)) -> List(a) {
  case result {
    Ok(items) -> items
    Error(Nil) -> []
  }
}

// --- Help ------------------------------------------------------------------

/// The key list and the record of games played. Same width as the board, so
/// the caller can centre it the same way.
pub fn help(record: Stats, options: Options) -> List(String) {
  let cells = case options.suits {
    Symbols -> "♣ ♦ ♥ ♠"
    Letters -> "C D H S"
  }
  list.map(
    [
      "",
      margin <> "Keys",
      "",
      key_line("1 - 8", "pick up a column"),
      key_line("a s d f", "pick up a free cell"),
      key_line("space", "send the card home (" <> cells <> ")"),
      key_line("esc", "put the card back"),
      key_line("u   r", "undo, redo"),
      key_line("n", "deal a new game"),
      key_line("p", "auto-play to the foundations on/off"),
      key_line("?", "this screen"),
      key_line("q", "quit"),
      "",
      margin <> "Record",
      "",
      margin <> "  " <> stats.summary(record),
      "",
      margin <> "? or esc to go back",
    ],
    string.trim_end,
  )
}

fn key_line(keys: String, meaning: String) -> String {
  margin <> "  " <> pad(keys, 10) <> meaning
}

fn pad(text: String, width: Int) -> String {
  text <> string.repeat(" ", int.max(width - string.length(text), 0))
}
