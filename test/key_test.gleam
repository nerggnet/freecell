import freecell/tui/key.{
  Backspace, Char, Ctrl, Down, Enter, Escape, Left, Right, Space, Tab, Unknown,
  Up,
}
import gleam/list

pub fn printable_bytes_become_characters_test() {
  assert key.from_byte(0x31) == Char("1")
  assert key.from_byte(0x61) == Char("a")
  assert key.from_byte(0x71) == Char("q")
  assert key.from_byte(0x5a) == Char("Z")
  assert key.from_byte(0x3f) == Char("?")
}

pub fn named_keys_test() {
  assert key.from_byte(9) == Tab
  assert key.from_byte(10) == Enter
  assert key.from_byte(13) == Enter
  assert key.from_byte(27) == Escape
  assert key.from_byte(32) == Space
  assert key.from_byte(8) == Backspace
  assert key.from_byte(127) == Backspace
}

/// Control characters are the letter typed with Ctrl, 64 lower.
pub fn control_characters_test() {
  assert key.from_byte(3) == Ctrl("c")
  assert key.from_byte(4) == Ctrl("d")
  assert key.from_byte(26) == Ctrl("z")
}

pub fn arrow_keys_come_from_the_final_byte_test() {
  assert key.from_final_byte(0x41) == Up
  assert key.from_final_byte(0x42) == Down
  assert key.from_final_byte(0x43) == Right
  assert key.from_final_byte(0x44) == Left
  assert key.from_final_byte(0x7e) == Unknown
}

/// A CSI sequence runs until its first byte in 0x40-0x7e; everything before
/// that is parameters.
pub fn sequence_terminators_test() {
  list.each([0x41, 0x42, 0x43, 0x44, 0x6d, 0x7e], fn(byte) {
    assert key.ends_sequence(byte)
  })
  // Digits and the parameter separator keep the sequence going.
  list.each([0x30, 0x39, 0x3b, 0x3f], fn(byte) {
    assert !key.ends_sequence(byte)
  })
}

pub fn bytes_above_ascii_are_not_guessed_at_test() {
  assert key.from_byte(0x80) == Unknown
  assert key.from_byte(0xff) == Unknown
}
