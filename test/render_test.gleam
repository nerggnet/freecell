import fixture
import freecell/board
import freecell/card
import freecell/deck
import freecell/location.{Cascade, Free}
import freecell/render.{type View, Letters, Options, Selection, Symbols, View}
import freecell/rules
import freecell/stats
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Nothing may exceed the board width, or the screen tears on a narrow
/// terminal. Measured in graphemes: "A♠" is two columns but four bytes.
const board_width = 64

fn view_of(number: Int) -> View {
  let assert Ok(dealt) = board.new(deck.deal(number))
  View(..view_on(dealt), number: number)
}

fn view_on(board: board.Board) -> View {
  View(
    board: board,
    number: 1,
    moves: 0,
    selection: None,
    message: "",
    elapsed: 0,
    carry: Some(rules.carrying_capacity(board)),
    stuck: rules.is_stuck(rules.Standard, board),
  )
}

/// The whole screen for game 1, exactly. Any layout change has to be looked at
/// and accepted deliberately rather than slipping through.
pub fn game_one_renders_exactly_this_test() {
  let expected = [
    "",
    "  FreeCell #1                       5 at a time · 0:00 · moves 0",
    "",
    "    a      s      d      f             ♣      ♦      ♥      ♠",
    "  ╭╌╌╌╌╮ ╭╌╌╌╌╮ ╭╌╌╌╌╮ ╭╌╌╌╌╮        ╭╌╌╌╌╮ ╭╌╌╌╌╮ ╭╌╌╌╌╮ ╭╌╌╌╌╮",
    "  ╎    ╎ ╎    ╎ ╎    ╎ ╎    ╎        ╎    ╎ ╎    ╎ ╎    ╎ ╎    ╎",
    "  ╰╌╌╌╌╯ ╰╌╌╌╌╯ ╰╌╌╌╌╯ ╰╌╌╌╌╯        ╰╌╌╌╌╯ ╰╌╌╌╌╯ ╰╌╌╌╌╯ ╰╌╌╌╌╯",
    "",
    "    1       2       3       4       5       6       7       8",
    "  │ J♦ │  │ 2♦ │  │ 9♥ │  │ J♣ │  │ 5♦ │  │ 7♥ │  │ 7♣ │  │ 5♥ │",
    "  │ K♦ │  │ K♣ │  │ 9♠ │  │ 5♠ │  │ A♦ │  │ Q♣ │  │ K♥ │  │ 3♥ │",
    "  │ 2♠ │  │ K♠ │  │ 9♦ │  │ Q♦ │  │ J♠ │  │ A♠ │  │ A♥ │  │ 3♣ │",
    "  │ 4♣ │  │ 5♣ │  │ T♠ │  │ Q♥ │  │ 4♥ │  │ A♣ │  │ 4♦ │  │ 7♠ │",
    "  │ 3♠ │  │ T♦ │  │ 4♠ │  │ T♥ │  │ 8♥ │  │ 2♣ │  │ J♥ │  │ 7♦ │",
    "  │ 6♦ │  │ 8♠ │  │ 8♦ │  │ Q♠ │  ├────┤  ├────┤  ├────┤  ├────┤",
    "  ├────┤  ├────┤  ├────┤  ├────┤  │ 6♣ │  │ 3♦ │  │ 8♣ │  │ T♣ │",
    "  │ 6♠ │  │ 9♣ │  │ 2♥ │  │ 6♥ │  ╰────╯  ╰────╯  ╰────╯  ╰────╯",
    "  ╰────╯  ╰────╯  ╰────╯  ╰────╯",
    "",
    "",
    "  1-8 · asdf · space home · u undo · h hint · ? keys · q quit",
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
  let assert Ok(first_row) = lines |> list.drop(9) |> list.first
  assert string.contains(first_row, "JD")
  // The frames fall back to ASCII too, or the board would be half drawn.
  list.each(lines, fn(line) {
    assert !string.contains(line, "│")
    assert !string.contains(line, "╭")
  })
}

/// A selected column marks the whole run that would travel, not just the card
/// on the end of it.
pub fn a_selected_run_is_marked_test() {
  let picked = View(..view_of(1), selection: Some(Selection(Cascade(0), 1)))
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
      View(..view_on(parked), selection: Some(Selection(Free(1), 1))),
      render.plain(),
    )
  assert list.any(lines, fn(line) { string.contains(line, ">6♠<") })
  // The unselected cells stay empty.
  assert list.any(lines, fn(line) { string.contains(line, "╎    ╎") })
}

/// Every empty slot is drawn as an empty card rather than left blank, so the
/// board shows where cards can go.
pub fn empty_slots_are_drawn_as_empty_cards_test() {
  let lines = render.frame(view_of(1), render.plain())
  let assert Ok(faces) = lines |> list.drop(5) |> list.first
  assert faces
    == "  ╎    ╎ ╎    ╎ ╎    ╎ ╎    ╎        ╎    ╎ ╎    ╎ ╎    ╎ ╎    ╎"
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

fn header_at(seconds: Int) -> String {
  header_of(View(..view_of(1), elapsed: seconds))
}

fn header_of(view: View) -> String {
  let assert Ok(header) =
    render.frame(view, render.plain()) |> list.drop(1) |> list.first
  header
}

pub fn the_header_shows_a_clock_test() {
  assert string.contains(header_at(0), "0:00")
  // Seconds are padded, so the header does not jitter as it ticks.
  assert string.contains(header_at(5), "0:05")
  assert string.contains(header_at(90), "1:30")
  assert string.contains(header_at(3599), "59:59")
}

/// The header holds four things and none of them may push it over the edge.
pub fn a_crowded_header_still_fits_test() {
  assert string.length(header_at(3599)) <= board_width

  let roomy = fixture.board_from(["KS", "KH", "", "", "", "", "", ""])
  let crowded =
    View(..view_on(roomy), number: 32_000, moves: 999, elapsed: 3599)
  assert string.length(header_of(crowded)) <= board_width
}

/// The tallest a cascade can ever become is nineteen cards: a dealt seven
/// whose exposed card is a king, with a full queen-to-ace run laid on it.
/// Nothing in FreeCell can build higher, so if the board fits at nineteen it
/// fits always.
pub fn the_tallest_board_the_game_can_reach_fits_thirty_five_rows_test() {
  let tall =
    fixture.board_from([
      "KS QH JS TH 9S 8H 7S 6H 5S 4H 3S 2H AS KD QC JD TC 9D 8C",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ])
  let assert Ok(pile) = board.cascade_display(tall, 0)
  assert list.length(pile) == 19

  let lines = render.frame(view_on(tall), render.plain())
  assert list.length(lines) <= 35
  // Ten rows of chrome, plus the pile and the two rows that frame its foot.
  assert list.length(lines) == 14 + 19
}

/// A column of one card is a whole card: a top edge, the face, and a base.
pub fn a_single_card_column_is_drawn_as_one_card_test() {
  let lonely = fixture.board_from(["KS", "", "", "", "", "", "", ""])
  let lines = render.frame(view_on(lonely), render.plain())
  let drawn =
    lines
    |> list.drop(9)
    |> list.take(3)
    |> list.map(fn(line) { string.slice(line, 2, 6) })
  assert drawn == ["╭────╮", "│ K♠ │", "╰────╯"]
}

/// The cap moves above whatever is being lifted, so a run in hand reads as one
/// block rather than being cut in two by the line above the foot.
pub fn the_cap_sits_above_the_cards_in_hand_test() {
  let held = fixture.board_from(["KS QH JS TH", "", "", "", "", "", "", ""])
  let lines =
    render.frame(
      View(..view_on(held), selection: Some(Selection(Cascade(0), 3))),
      render.plain(),
    )
  let drawn =
    lines
    |> list.drop(9)
    |> list.take(6)
    |> list.map(fn(line) { string.slice(line, 2, 6) })
  assert drawn == ["│ K♠ │", "├────┤", "│>Q♥<│", "│>J♠<│", "│>T♥<│", "╰────╯"]
}

/// The header carries the number that answers "why will this not move?".
///
/// With every free cell full and no empty column it really is one, and cards
/// really do move one at a time — which otherwise reads as the game refusing
/// to shift a run.
pub fn the_header_counts_what_can_be_carried_test() {
  assert string.contains(header_of(view_of(1)), "5 at a time")

  let packed =
    fixture.board_from(["KS", "KH", "KD", "KC", "QS", "QH", "QD", "QC"])
    |> fixture.with_cells(["2C", "2D", "2H", "2S"])
  assert string.contains(header_of(view_on(packed)), "1 at a time")

  // Six empty columns doubling five times over: 5 x 2^6.
  let roomy = fixture.board_from(["KS", "KH", "", "", "", "", "", ""])
  assert rules.carrying_capacity(roomy) == 320
  assert string.contains(header_of(view_on(roomy)), "320 at a time")
}

pub fn the_help_explains_carrying_test() {
  let shown = render.help(stats.empty(), render.plain()) |> string.join("\n")
  assert string.contains(shown, "Carrying")
  assert string.contains(shown, "doubled for every empty column")
}
