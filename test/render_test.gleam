import fixture
import freecell/board
import freecell/card
import freecell/deck
import freecell/location.{Cascade, Free}
import freecell/render.{type View, Letters, Options, Symbols, View}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Nothing may exceed the board width, or the screen tears on a narrow
/// terminal. Measured in graphemes: "A♠" is two columns but four bytes.
const board_width = 55

fn view_of(number: Int) -> View {
  let assert Ok(dealt) = board.new(deck.deal(number))
  View(board: dealt, number: number, moves: 0, selection: None, message: "")
}

fn view_on(board: board.Board) -> View {
  View(board: board, number: 1, moves: 0, selection: None, message: "")
}

/// The whole screen for game 1, exactly. Any layout change has to be looked at
/// and accepted deliberately rather than slipping through.
pub fn game_one_renders_exactly_this_test() {
  let expected = [
    "",
    "  FreeCell #1                                   moves 0",
    "",
    "   a    s    d    f                  ♣    ♦    ♥    ♠",
    "  [  ] [  ] [  ] [  ]               [  ] [  ] [  ] [  ]",
    "",
    "   1      2      3      4      5      6      7      8",
    "   J♦     2♦     9♥     J♣     5♦     7♥     7♣     5♥",
    "   K♦     K♣     9♠     5♠     A♦     Q♣     K♥     3♥",
    "   2♠     K♠     9♦     Q♦     J♠     A♠     A♥     3♣",
    "   4♣     5♣     T♠     Q♥     4♥     A♣     4♦     7♠",
    "   3♠     T♦     4♠     T♥     8♥     2♣     J♥     7♦",
    "   6♦     8♠     8♦     Q♠     6♣     3♦     8♣     T♣",
    "   6♠     9♣     2♥     6♥",
    "",
    "",
    "  1-8 · asdf · u undo · h hint · ? keys · q quit",
  ]
  assert render.frame(view_of(1), render.plain()) == expected
}

pub fn no_line_is_wider_than_the_board_test() {
  list.each([1, 617, 11_982], fn(number) {
    list.each(render.frame(view_of(number), render.plain()), fn(line) {
      assert string.length(line) <= board_width
    })
  })
}

pub fn no_line_carries_trailing_blanks_test() {
  list.each(render.frame(view_of(1), render.plain()), fn(line) {
    assert line == string.trim_end(line)
  })
}

/// Colour must be decoration only: strip the escape sequences and what is left
/// has to be the plain rendering, character for character.
pub fn colour_changes_nothing_but_colour_test() {
  let coloured = Options(colour: True, suits: Symbols)
  let plain = render.frame(view_of(1), render.plain())
  let painted = render.frame(view_of(1), coloured)

  assert painted != plain
  assert list.map(painted, strip_escapes) == plain
}

pub fn letters_mode_avoids_symbols_test() {
  let ascii = Options(colour: False, suits: Letters)
  let lines = render.frame(view_of(1), ascii)
  list.each(lines, fn(line) {
    assert !string.contains(line, "♦")
    assert !string.contains(line, "♠")
  })
  let assert Ok(first_row) = lines |> list.drop(7) |> list.first
  assert string.contains(first_row, "JD")
}

/// A selected column marks the whole run that would travel, not just the card
/// on the end of it.
pub fn a_selected_run_is_marked_test() {
  let picked = View(..view_of(1), selection: Some(Cascade(0)))
  let lines = render.frame(picked, render.plain())
  // Column 1 of game 1 ends 6♦ 6♠, which is not a run, so only 6♠ is taken.
  assert list.any(lines, fn(line) { string.contains(line, ">6♠<") })
  assert !list.any(lines, fn(line) { string.contains(line, ">6♦<") })
}

pub fn a_selected_free_cell_is_marked_test() {
  let parked =
    fixture.board_from(list.repeat("", 8))
    |> fixture.with_cells(["", "6S", "", ""])
  let lines =
    render.frame(
      View(..view_on(parked), selection: Some(Free(1))),
      render.plain(),
    )
  assert list.any(lines, fn(line) { string.contains(line, ">6♠<") })
  // The unselected cells keep their brackets.
  assert list.any(lines, fn(line) { string.contains(line, "[  ]") })
}

pub fn foundations_show_their_top_card_test() {
  let lines = render.frame(view_of(1), render.plain())
  let assert Ok(holders) = lines |> list.drop(4) |> list.first
  assert holders == "  [  ] [  ] [  ] [  ]               [  ] [  ] [  ] [  ]"
}

pub fn the_header_counts_moves_test() {
  let lines = render.frame(View(..view_of(1), moves: 1), render.plain())
  let assert Ok(header) = lines |> list.drop(1) |> list.first
  assert string.contains(header, "FreeCell #1")
  assert string.contains(header, "moves 1")
}

pub fn a_message_appears_in_the_status_line_test() {
  let lines =
    render.frame(
      View(..view_of(1), message: "nowhere to put that"),
      render.plain(),
    )
  assert list.any(lines, fn(line) {
    string.contains(line, "nowhere to put that")
  })
}

pub fn a_won_game_says_so_test() {
  let won =
    fixture.board_from(list.repeat("", 8))
    |> fixture.with_foundations([
      #(card.Clubs, 13),
      #(card.Diamonds, 13),
      #(card.Hearts, 13),
      #(card.Spades, 13),
    ])
  let lines =
    render.frame(View(..view_on(won), message: "ignored"), render.plain())
  assert list.any(lines, fn(line) { string.contains(line, "You win") })
  assert !list.any(lines, fn(line) { string.contains(line, "ignored") })
}

pub fn a_stuck_game_says_so_test() {
  let dead =
    fixture.board_from(["2C", "2D", "2H", "2S", "4C", "4D", "4H", "4S"])
    |> fixture.with_cells(["6C", "6D", "6H", "6S"])
  let lines = render.frame(view_on(dead), render.plain())
  assert list.any(lines, fn(line) { string.contains(line, "No moves left") })
}

/// Drops ANSI escape sequences: ESC, then anything up to the letter that ends
/// the sequence.
fn strip_escapes(text: String) -> String {
  scan(string.to_graphemes(text), False, [])
}

fn scan(chars: List(String), inside: Bool, kept: List(String)) -> String {
  case chars {
    [] -> kept |> list.reverse |> string.concat
    [char, ..rest] ->
      case inside, is_letter(char) {
        True, True -> scan(rest, False, kept)
        True, False -> scan(rest, True, kept)
        False, _ ->
          case char == "\u{1b}" {
            True -> scan(rest, True, kept)
            False -> scan(rest, False, [char, ..kept])
          }
      }
  }
}

fn is_letter(char: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", char)
}
