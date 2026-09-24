//// Turning bytes into keypresses. Pure, so the decoding is testable without
//// a terminal.

import gleam/string

pub type Key {
  Char(character: String)
  Enter
  Space
  Tab
  Backspace
  Escape
  Up
  Down
  Left
  Right
  Ctrl(letter: String)
  Unknown
}

/// A byte that is not part of an escape sequence.
pub fn from_byte(byte: Int) -> Key {
  case byte {
    9 -> Tab
    10 | 13 -> Enter
    27 -> Escape
    32 -> Space
    8 | 127 -> Backspace
    // Control characters are the letter they are typed with, less 64.
    code if code < 32 -> Ctrl(character_of(code + 96))
    code if code < 127 -> Char(character_of(code))
    _ -> Unknown
  }
}

/// The byte that ends a CSI escape sequence — the "A" of `ESC [ A`.
pub fn from_final_byte(byte: Int) -> Key {
  case byte {
    65 -> Up
    66 -> Down
    67 -> Right
    68 -> Left
    _ -> Unknown
  }
}

/// True for the byte that terminates a CSI sequence; the bytes before it are
/// parameters we have no use for.
pub fn ends_sequence(byte: Int) -> Bool {
  byte >= 0x40 && byte <= 0x7e
}

fn character_of(code: Int) -> String {
  case string.utf_codepoint(code) {
    Ok(point) -> string.from_utf_codepoints([point])
    Error(Nil) -> ""
  }
}
