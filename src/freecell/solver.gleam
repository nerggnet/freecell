//// A FreeCell solver, used for hints and for finishing a game off.
////
//// It also underwrites the tests: a rules engine is only as trustworthy as
//// its ability to play real numbered deals through to a win.
////
//// It is a best-first search. Positions are ranked by how many cards are
//// still off the foundations, with a nudge towards keeping cells and columns
//// free, and the most promising position is always expanded next. Plain
//// depth-first search wanders for hundreds of thousands of positions on deals
//// this one cracks in a few thousand.
////
//// It does not always succeed. A budget bounds the work, and some deals — 617
//// among them — defeat it entirely. Callers must be able to say so rather
//// than assume a solution exists.

import freecell/board.{type Board}
import freecell/card.{type Card}
import freecell/location.{type Location, Cascade, Foundation, Free}
import freecell/rules.{type Move, Move}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string

pub type Outcome {
  Solved(moves: List(#(Move, Int)), visited: Int)
  Unsolved(visited: Int, budget_spent: Bool)
}

type Node {
  Node(state: Board, path: List(#(Move, Int)))
}

type Search {
  Search(
    frontier: Dict(Int, List(Node)),
    seen: Set(String),
    visited: Int,
    budget: Int,
  )
}

pub fn solve(start: Board, budget: Int) -> Outcome {
  let opening = settle(start)
  let search =
    Search(frontier: dict.new(), seen: set.new(), visited: 0, budget: budget)
    |> push(Node(opening, []))
  explore(search)
}

fn explore(search: Search) -> Outcome {
  case search.visited >= search.budget {
    True -> Unsolved(search.visited, True)
    False ->
      case pop(search) {
        Error(Nil) -> Unsolved(search.visited, False)
        Ok(#(node, rest)) ->
          case rules.is_won(node.state) {
            True -> Solved(list.reverse(node.path), rest.visited)
            False -> explore(expand(rest, node))
          }
      }
  }
}

fn expand(search: Search, node: Node) -> Search {
  list.fold(candidates(node.state), search, fn(acc, entry) {
    let #(move, count) = entry
    case rules.apply_run(node.state, move, count) {
      // Generation is a cheap approximation of the rules; anything it gets
      // wrong is simply refused here and dropped.
      Error(_) -> acc
      Ok(next) -> push(acc, Node(settle(next), [entry, ..node.path]))
    }
  })
}

fn settle(state: Board) -> Board {
  // Safe promotions are never a mistake, so take them before branching.
  let #(next, _) = rules.auto_play(state)
  next
}

// --- Frontier --------------------------------------------------------------

fn push(search: Search, node: Node) -> Search {
  let id = fingerprint(node.state)
  case set.contains(search.seen, id) {
    True -> search
    False -> {
      let key = rank(node.state)
      let bucket = dict.get(search.frontier, key) |> result.unwrap([])
      Search(
        ..search,
        seen: set.insert(search.seen, id),
        frontier: dict.insert(search.frontier, key, [node, ..bucket]),
      )
    }
  }
}

fn pop(search: Search) -> Result(#(Node, Search), Nil) {
  use key <- result.try(dict.keys(search.frontier) |> list.reduce(int.min))
  case dict.get(search.frontier, key) {
    Ok([node, ..rest]) -> {
      let frontier = case rest {
        [] -> dict.delete(search.frontier, key)
        _ -> dict.insert(search.frontier, key, rest)
      }
      Ok(#(
        node,
        Search(..search, frontier: frontier, visited: search.visited + 1),
      ))
    }
    _ -> Error(Nil)
  }
}

/// Lower is better. Cards still off the foundations dominate; then comes how
/// deeply the next card each foundation wants is buried, which is what
/// actually stands between the position and progress. Free cells and empty
/// columns are worth a little.
fn rank(state: Board) -> Int {
  let home =
    list.fold(card.suits(), 0, fn(sum, suit) {
      sum + board.foundation(state, suit)
    })
  { 52 - home }
  * 10
  + buried(state)
  * 3
  - board.empty_free_cells(state)
  - 2
  * board.empty_cascades(state)
}

/// How many cards sit on top of the next card each foundation is waiting for.
fn buried(state: Board) -> Int {
  list.fold(card.suits(), 0, fn(sum, suit) {
    let wanted = board.foundation(state, suit) + 1
    case wanted > card.king {
      True -> sum
      False -> sum + depth_of(state, card.Card(wanted, suit))
    }
  })
}

fn depth_of(state: Board, target: Card) -> Int {
  board.cascades(state)
  |> list.filter_map(fn(cards) { index_of(cards, target) })
  |> list.first
  |> result.unwrap(0)
}

fn index_of(cards: List(Card), target: Card) -> Result(Int, Nil) {
  cards
  |> list.index_map(fn(held, index) { #(index, held) })
  |> list.filter(fn(pair) { pair.1 == target })
  |> list.map(fn(pair) { pair.0 })
  |> list.first
}

/// A position's identity for the visited set.
///
/// Cascades are interchangeable with one another, as are free cells, so both
/// are sorted: two layouts differing only in which column holds what are the
/// same position, and collapsing them cuts the search enormously.
fn fingerprint(state: Board) -> String {
  let columns =
    board.cascades(state)
    |> list.map(fn(cards) { cards |> list.map(card.to_code) |> string.join("") })
    |> list.sort(string.compare)
    |> string.join("/")

  let cells =
    board.free_cells(state)
    |> list.map(fn(cell) {
      case cell {
        None -> ".."
        Some(held) -> card.to_code(held)
      }
    })
    |> list.sort(string.compare)
    |> string.join("")

  let piles =
    card.suits()
    |> list.map(fn(suit) { int.to_string(board.foundation(state, suit)) })
    |> string.join(",")

  columns <> "|" <> cells <> "|" <> piles
}

// --- Move generation -------------------------------------------------------

/// Moves worth trying. Deliberately cheap: it proposes, `rules` disposes.
fn candidates(state: Board) -> List(#(Move, Int)) {
  let from_cascades =
    list.flat_map(indices(board.cascade_count), fn(index) {
      leaving(state, Cascade(index))
    })
  let from_cells =
    list.flat_map(indices(board.free_cell_count), fn(index) {
      leaving(state, Free(index))
    })
  list.append(from_cascades, from_cells)
}

fn leaving(state: Board, from: Location) -> List(#(Move, Int)) {
  case board.exposed(state, from) {
    Error(Nil) -> []
    Ok(top) -> {
      let run = rules.run_length(state, from)
      list.flatten([
        to_foundation(state, from, top),
        list.flat_map(indices(board.cascade_count), fn(index) {
          onto_cascade(state, from, top, run, index)
        }),
        to_free_cell(state, from),
      ])
    }
  }
}

fn to_foundation(
  state: Board,
  from: Location,
  top: Card,
) -> List(#(Move, Int)) {
  case board.foundation(state, top.suit) == top.rank - 1 {
    True -> [#(Move(from, Foundation(top.suit)), 1)]
    False -> []
  }
}

/// Only the first empty cell is worth trying; the others reach the same
/// position by a different name.
fn to_free_cell(state: Board, from: Location) -> List(#(Move, Int)) {
  case from {
    // Shuffling between cells achieves nothing.
    Free(_) -> []
    _ ->
      case first_index(board.free_cells(state), fn(cell) { cell == None }) {
        Ok(index) -> [#(Move(from, Free(index)), 1)]
        Error(Nil) -> []
      }
  }
}

fn onto_cascade(
  state: Board,
  from: Location,
  top: Card,
  run: Int,
  index: Int,
) -> List(#(Move, Int)) {
  case from == Cascade(index) {
    True -> []
    False -> {
      let room = rules.capacity(state, Cascade(index))
      case board.cascade(state, index) {
        Error(Nil) -> []

        Ok([]) -> {
          let count = int.min(run, room)
          let held = case from {
            Cascade(source) ->
              board.cascade(state, source)
              |> result.unwrap([])
              |> list.length
            _ -> 1
          }
          // Emptying one column to fill another just renames it.
          case count >= 1 && held > count && only_first_gap(state, index) {
            True -> [#(Move(from, Cascade(index)), count)]
            False -> []
          }
        }

        // A run descends by one from its exposed card, so exactly one of its
        // cards can sit on a given card: the one whose rank is one below it.
        Ok([onto, ..]) -> {
          let count = onto.rank - top.rank
          case count >= 1 && count <= run && count <= room {
            False -> []
            True ->
              case anchor(state, from, count) {
                Ok(deepest) ->
                  case rules.can_stack(deepest, onto) {
                    True -> [#(Move(from, Cascade(index)), count)]
                    False -> []
                  }
                Error(Nil) -> []
              }
          }
        }
      }
    }
  }
}

fn anchor(state: Board, from: Location, count: Int) -> Result(Card, Nil) {
  case from {
    Cascade(source) -> {
      use cards <- result.try(board.cascade(state, source))
      cards |> list.drop(count - 1) |> list.first
    }
    _ -> board.exposed(state, from)
  }
}

fn only_first_gap(state: Board, index: Int) -> Bool {
  first_index(board.cascades(state), list.is_empty) == Ok(index)
}

fn first_index(items: List(a), matching: fn(a) -> Bool) -> Result(Int, Nil) {
  items
  |> list.index_map(fn(item, index) { #(index, item) })
  |> list.filter(fn(pair) { matching(pair.1) })
  |> list.map(fn(pair) { pair.0 })
  |> list.first
}

fn indices(count: Int) -> List(Int) {
  int.range(from: count - 1, to: -1, with: [], run: fn(acc, index) {
    [index, ..acc]
  })
}
