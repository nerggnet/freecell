//// Terminal escape sequences.
////
//// Kept in one place so the renderer can be asked for plain text instead,
//// which is what the golden tests compare against.

const escape = "\u{1b}["

pub fn red(text: String) -> String {
  escape <> "31m" <> text <> escape <> "39m"
}

pub fn black(text: String) -> String {
  escape <> "30m" <> text <> escape <> "39m"
}

/// A card face: dark ink on pale stock. The foreground is always set
/// alongside it, because the terminal's own text colour is usually light and
/// would vanish against this.
pub fn on_paper(text: String) -> String {
  escape <> "47m" <> text <> escape <> "49m"
}

/// A card that has been picked up.
pub fn on_held(text: String) -> String {
  escape <> "103m" <> text <> escape <> "49m"
}

pub fn dim(text: String) -> String {
  escape <> "2m" <> text <> escape <> "22m"
}

pub fn bold(text: String) -> String {
  escape <> "1m" <> text <> escape <> "22m"
}

/// Swap foreground and background, used to mark the current selection.
pub fn inverse(text: String) -> String {
  escape <> "7m" <> text <> escape <> "27m"
}

// --- Screen control --------------------------------------------------------

/// Switch to the alternate screen, so the player's scrollback survives.
pub fn enter_full_screen() -> String {
  escape <> "?1049h"
}

pub fn leave_full_screen() -> String {
  escape <> "?1049l"
}

pub fn hide_cursor() -> String {
  escape <> "?25l"
}

pub fn show_cursor() -> String {
  escape <> "?25h"
}

pub fn clear_screen() -> String {
  escape <> "2J" <> escape <> "H"
}

pub fn move_to_home() -> String {
  escape <> "H"
}

/// Erase from the cursor to the end of the line, so a shorter line does not
/// leave the tail of a longer one behind it.
pub fn clear_to_end_of_line() -> String {
  escape <> "K"
}

/// Erase from the cursor to the bottom of the screen, so a frame that grew
/// shorter does not leave the old one's tail behind.
pub fn clear_to_end_of_screen() -> String {
  escape <> "J"
}
