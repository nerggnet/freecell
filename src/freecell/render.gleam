//// Drawing the board.
////
//// Pure: it returns lines of text and never writes anything. Colour is
//// optional and, when off, the result is plain text the tests can compare
//// against character for character.
////
//// Every slot is exactly `slot_width` columns wide. Colour is applied
//// *inside* that width and never padded around, so the layout arithmetic only
//// ever measures plain text — which matters, because an escape sequence has
//// length but no width, and `A♠` has two columns but four bytes.

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

/// Every frame is exactly this wide, so callers can centre it.
pub const board_width = 64

const margin = "  "

/// The card face between its two rails: " J♦ ".
const face_width = 4

/// A whole slot, rails included.
const slot_width = 6

const slot_gap = "  "

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

/// What the player is holding: where it came from, and how many cards.
pub type Selection {
  Selection(place: Location, cards: Int)
}

/// Everything the screen shows. Deliberately not a `Game`: the renderer has
/// no business knowing about history or undo, and tests can build a view from
/// any board without playing a game to reach it.
pub type View {
  View(
    board: Board,
    number: Int,
    moves: Int,
    selection: Option(Selection),
    message: String,
    /// Seconds since the deal.
    elapsed: Int,
    /// How many cards can travel as one onto an occupied column.
    carry: Int,
  )
}

/// The characters cards are drawn with. Box drawing where the terminal will
/// take it, plain ASCII where it will not.
type Edges {
  Edges(
    top_left: String,
    top_right: String,
    bottom_left: String,
    bottom_right: String,
    join_left: String,
    join_right: String,
    edge: String,
    rail: String,
    /// For a slot with nothing in it.
    faint_edge: String,
    faint_rail: String,
  )
}

fn edges_for(options: Options) -> Edges {
  case options.suits {
    Symbols ->
      Edges(
        top_left: "╭",
        top_right: "╮",
        bottom_left: "╰",
        bottom_right: "╯",
        join_left: "├",
        join_right: "┤",
        edge: "─",
        rail: "│",
        faint_edge: "╌",
        faint_rail: "╎",
      )
    Letters ->
      Edges(
        top_left: "+",
        top_right: "+",
        bottom_left: "+",
        bottom_right: "+",
        join_left: "+",
        join_right: "+",
        edge: "-",
        rail: "|",
        faint_edge: ".",
        faint_rail: ":",
      )
  }
}

/// The whole screen, as lines. Every line is at most `board_width` wide.
pub fn frame(view: View, options: Options) -> List(String) {
  let state = view.board
  let edges = edges_for(options)
  // Trailing blanks would leave debris on the screen when a line shrinks.
  list.map(
    list.flatten([
      ["", title(view), ""],
      [holder_labels(options)],
      holders(state, view, options, edges),
      [""],
      [column_labels()],
      cascades(state, view, options, edges),
      ["", status(view), hints()],
    ]),
    string.trim_end,
  )
}

// --- Header ----------------------------------------------------------------

fn title(view: View) -> String {
  let left = "FreeCell #" <> int.to_string(view.number)
  // The carrying capacity leads, because it is the number that answers "why
  // will this not move?" — and when it is 1, cards really do move one at a
  // time, which otherwise looks like the game refusing to shift a run.
  let right =
    int.to_string(view.carry)
    <> " at a time · "
    <> clock(view.elapsed)
    <> " · moves "
    <> int.to_string(view.moves)
  margin <> spread(left, right, board_width - string.length(margin))
}

/// Minutes and seconds. Hours would need a wider header and nobody should be
/// playing one deal that long.
fn clock(seconds: Int) -> String {
  int.to_string(seconds / 60)
  <> ":"
  <> string.pad_start(int.to_string(seconds % 60), 2, "0")
}

fn holder_labels(options: Options) -> String {
  let cells = list.map(cell_keys, fn(key) { centre(key, slot_width) })
  let piles =
    list.map(card.suits(), fn(suit) {
      centre(
        case options.suits {
          Symbols -> card.suit_symbol(suit)
          Letters -> card.suit_letter(suit)
        },
        slot_width,
      )
    })
  two_groups(cells, piles)
}

/// Free cells and foundations, each drawn as a card in its own right. Three
/// rows: the top edge, the face, the bottom edge.
fn holders(
  state: Board,
  view: View,
  options: Options,
  edges: Edges,
) -> List(String) {
  let cells =
    list.index_map(board.free_cells(state), fn(held, index) {
      holder(held, picked(view, Free(index)), options, edges)
    })
  let piles =
    list.map(card.suits(), fn(suit) {
      let top = case board.foundation(state, suit) {
        0 -> None
        rank -> Some(card.Card(rank, suit))
      }
      holder(top, False, options, edges)
    })

  [
    two_groups(list.map(cells, fn(h) { h.0 }), list.map(piles, fn(h) { h.0 })),
    two_groups(list.map(cells, fn(h) { h.1 }), list.map(piles, fn(h) { h.1 })),
    two_groups(list.map(cells, fn(h) { h.2 }), list.map(piles, fn(h) { h.2 })),
  ]
}

fn holder(
  content: Option(Card),
  selected: Bool,
  options: Options,
  edges: Edges,
) -> #(String, String, String) {
  case content {
    None -> #(
      faint_top(edges),
      edges.faint_rail <> string.repeat(" ", face_width) <> edges.faint_rail,
      faint_bottom(edges),
    )
    Some(held) -> #(
      solid_top(edges),
      face(held, selected, options, edges),
      solid_bottom(edges),
    )
  }
}

fn picked(view: View, place: Location) -> Bool {
  case view.selection {
    Some(Selection(held, _)) -> held == place
    None -> False
  }
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
    list.map(columns(), fn(index) {
      centre(int.to_string(index + 1), slot_width)
    })
  margin <> string.join(labels, slot_gap)
}

/// Buried cards are sleeved into a stack; the card at the foot, the one that
/// can actually be played, gets its own top edge and base so it reads as a
/// whole card sitting on the pile.
///
/// Every column occupies its own card count plus two rows — the cap above the
/// exposed card and the base below it — so a column of one card is a complete
/// little card, and an empty column is just the cap and base with nothing
/// between them.
fn cascades(
  state: Board,
  view: View,
  options: Options,
  edges: Edges,
) -> List(String) {
  let piles = list.map(columns(), fn(index) { display_column(state, index) })
  let depth = piles |> list.map(list.length) |> list.fold(0, int.max)

  list.map(indices(depth + 2), fn(row) {
    let cells =
      list.index_map(piles, fn(pile, column) {
        let count = list.length(pile)
        let from = selection_starts_at(view, column, count)
        // The cap sits above whatever is being lifted: the cards in hand if
        // this column holds them, otherwise the single card at the foot.
        let cap = int.min(from, int.max(count - 1, 0))
        column_row(pile, row, cap, from, options, edges)
      })
    margin <> string.join(cells, slot_gap)
  })
}

fn column_row(
  pile: List(Card),
  row: Int,
  cap: Int,
  from: Int,
  options: Options,
  edges: Edges,
) -> String {
  let count = list.length(pile)
  case count == 0 {
    True ->
      case row {
        0 -> faint_top(edges)
        1 -> faint_bottom(edges)
        _ -> blank()
      }
    False ->
      case row {
        // The sleeved part of the pile, above the cap.
        r if r < cap -> sleeved(pile, r, from, options, edges)
        // The cap itself. With nothing above it, it is a top edge rather than
        // a join, which is what makes a column of one card a whole card.
        r if r == cap ->
          case cap {
            0 -> solid_top(edges)
            _ -> join(edges)
          }
        // Below the cap the rows are offset by one, the cap having taken a row
        // of its own.
        r if r <= count -> sleeved(pile, r - 1, from, options, edges)
        r if r == count + 1 -> solid_bottom(edges)
        _ -> blank()
      }
  }
}

fn sleeved(
  pile: List(Card),
  index: Int,
  from: Int,
  options: Options,
  edges: Edges,
) -> String {
  case pile |> list.drop(index) |> list.first {
    Ok(held) -> face(held, index >= from, options, edges)
    Error(Nil) -> blank()
  }
}

fn display_column(state: Board, index: Int) -> List(Card) {
  board.cascade_display(state, index) |> unwrap_list
}

/// The display row at which this column's selection begins. A column that is
/// not selected reports a row past its own end, so nothing is marked.
fn selection_starts_at(view: View, column: Int, depth: Int) -> Int {
  case view.selection {
    Some(Selection(Cascade(index), cards)) if index == column -> depth - cards
    _ -> depth + 1
  }
}

// --- Card faces and edges --------------------------------------------------

/// A card between its rails. Picked-up cards are marked with angles as well as
/// colour, so the selection is visible in plain text too.
fn face(held: Card, selected: Bool, options: Options, edges: Edges) -> String {
  let printed = ink(face_of(held, options), held, options)
  let inner = case selected {
    True -> ">" <> printed <> "<"
    False -> " " <> printed <> " "
  }
  edges.rail <> stock(inner, selected, options) <> edges.rail
}

fn face_of(held: Card, options: Options) -> String {
  case options.suits {
    Symbols -> card.to_string(held)
    Letters -> card.to_code(held)
  }
}

/// The pips. Both colours are set explicitly: against pale stock the
/// terminal's own foreground is usually too light to read.
fn ink(text: String, held: Card, options: Options) -> String {
  case options.colour {
    False -> text
    True ->
      case card.color(held.suit) {
        card.Red -> ansi.red(text)
        card.Black -> ansi.black(text)
      }
  }
}

fn stock(text: String, selected: Bool, options: Options) -> String {
  case options.colour, selected {
    False, _ -> text
    True, True -> ansi.on_held(text)
    True, False -> ansi.on_paper(text)
  }
}

fn solid_top(edges: Edges) -> String {
  edges.top_left <> string.repeat(edges.edge, face_width) <> edges.top_right
}

fn solid_bottom(edges: Edges) -> String {
  edges.bottom_left
  <> string.repeat(edges.edge, face_width)
  <> edges.bottom_right
}

fn join(edges: Edges) -> String {
  edges.join_left <> string.repeat(edges.edge, face_width) <> edges.join_right
}

fn faint_top(edges: Edges) -> String {
  edges.top_left
  <> string.repeat(edges.faint_edge, face_width)
  <> edges.top_right
}

fn faint_bottom(edges: Edges) -> String {
  edges.bottom_left
  <> string.repeat(edges.faint_edge, face_width)
  <> edges.bottom_right
}

fn blank() -> String {
  string.repeat(" ", slot_width)
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
  margin <> "1-8 · asdf · space home · u undo · h hint · ? keys · q quit"
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
      key_line("up down", "take more or fewer cards"),
      key_line("esc", "put the card back"),
      key_line("u   r", "undo, redo"),
      key_line("n", "deal a new game"),
      key_line("R", "start this deal again"),
      key_line("h", "suggest a move, if there is one"),
      key_line("!", "finish the game, if it can be finished"),
      key_line("p", "auto-play to the foundations on/off"),
      key_line("?", "this screen"),
      key_line("q", "quit"),
      "",
      margin <> "Carrying",
      "",
      margin <> "  The header counts how many cards move as one: your free",
      margin <> "  cells plus one, doubled for every empty column. Moving",
      margin <> "  into an empty column spends it, so that carries half.",
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
