//// The terminal edge of the game.
////
//// Everything impure lives behind this module, so the rest of the codebase
//// stays pure and testable.

import freecell/tui/key

@external(erlang, "freecell_ffi", "start_raw")
fn ffi_start_raw() -> Result(Nil, String)

@external(erlang, "freecell_ffi", "read_byte")
fn ffi_read_byte() -> Result(BitArray, Nil)

@external(erlang, "freecell_ffi", "await_input")
fn ffi_await_input() -> Input

@external(erlang, "freecell_ffi", "read_input")
fn ffi_read_input(timeout: Int) -> Input

/// A keypress, nothing within the deadline, or stdin closing under us.
pub type Input {
  Byte(value: Int)
  Timeout
  Closed
}

/// How long to wait for the rest of an escape sequence before concluding that
/// Escape was pressed on its own. A real sequence arrives in one burst, so
/// this only ever delays a bare Escape.
const escape_grace_ms = 30

/// Put the terminal into raw mode. Fails if something already claimed
/// stdin, which is what happens when the VM was booted with a shell.
pub fn enter_raw() -> Result(Nil, String) {
  ffi_start_raw()
}

/// Read a single byte, blocking until one arrives. Multi-byte keys such as
/// the arrows arrive as several consecutive calls.
pub fn read_byte() -> Result(Int, Nil) {
  case ffi_read_byte() {
    Ok(<<byte:8>>) -> Ok(byte)
    Ok(_) -> Error(Nil)
    Error(Nil) -> Error(Nil)
  }
}

/// Read one keypress, assembling escape sequences as they arrive.
pub fn read_key() -> Result(key.Key, Nil) {
  case ffi_await_input() {
    Closed -> Error(Nil)
    Timeout -> Error(Nil)
    Byte(27) -> read_escape()
    Byte(byte) -> Ok(key.from_byte(byte))
  }
}

fn read_escape() -> Result(key.Key, Nil) {
  case ffi_read_input(escape_grace_ms) {
    // Nothing followed, so Escape was pressed by itself.
    Timeout -> Ok(key.Escape)
    Closed -> Error(Nil)
    // CSI and SS3 both introduce the sequences we care about.
    Byte(0x5b) | Byte(0x4f) -> read_sequence()
    // Some other ESC-prefixed key; treat it as Escape rather than acting on it.
    Byte(_) -> Ok(key.Escape)
  }
}

fn read_sequence() -> Result(key.Key, Nil) {
  case ffi_read_input(escape_grace_ms) {
    Timeout -> Ok(key.Escape)
    Closed -> Error(Nil)
    Byte(byte) ->
      case key.ends_sequence(byte) {
        True -> Ok(key.from_final_byte(byte))
        // A parameter byte; keep going until the sequence ends.
        False -> read_sequence()
      }
  }
}

/// Terminal size as #(columns, rows), falling back to 80x24.
@external(erlang, "freecell_ffi", "term_size")
pub fn size() -> #(Int, Int)

/// Write without a trailing newline. In raw mode a bare "\n" does not return
/// the carriage, so callers emit "\r\n" themselves.
@external(erlang, "freecell_ffi", "write")
pub fn write(text: String) -> Nil

/// Command-line arguments, excluding the runtime's own.
@external(erlang, "freecell_ffi", "arguments")
pub fn arguments() -> List(String)

/// Microseconds since the epoch, used only to seed the shuffle.
@external(erlang, "freecell_ffi", "now_micros")
pub fn now() -> Int

/// Where the record of games played is kept.
@external(erlang, "freecell_ffi", "stats_path")
pub fn stats_path() -> String

@external(erlang, "freecell_ffi", "read_file")
pub fn read_file(path: String) -> Result(String, Nil)

@external(erlang, "freecell_ffi", "write_file")
pub fn write_file(path: String, contents: String) -> Result(Nil, Nil)

/// The version this build was made from.
@external(erlang, "freecell_ffi", "version")
pub fn version() -> String
