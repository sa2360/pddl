// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// Maximum S-expression nesting accepted by the generic reader.
const MAX_SEXP_DEPTH : Int = 1024

///|
/// Generic S-expression node. The semantic parser consumes this tree, which
/// keeps parenthesis handling and line/column bookkeeping in one place.
priv enum Sexp {
  SAtom(String, Position)
  SVar(String, Position)
  SList(Array[Sexp], Position)
}

///|
fn parse_sexps(tokens : Array[Token]) -> Array[Sexp] raise PddlError {
  let result : Array[Sexp] = []
  let mut i = 0
  while i < tokens.length() {
    let (node, next) = parse_sexp_at(tokens, i, 0)
    result.push(node)
    i = next
  }
  result
}

///|
fn parse_sexp_at(
  tokens : Array[Token],
  start : Int,
  depth : Int,
) -> (Sexp, Int) raise PddlError {
  let tok = tokens[start]
  match tok.kind {
    LParen => {
      if depth >= MAX_SEXP_DEPTH {
        raise syntax_error(
          tok.pos,
          "S-expression nesting exceeds the limit of \{MAX_SEXP_DEPTH}",
        )
      }
      let items : Array[Sexp] = []
      let mut i = start + 1
      let mut closed = false
      while i < tokens.length() {
        match tokens[i].kind {
          RParen => {
            closed = true
            i += 1
            break
          }
          _ => {
            let (child, next) = parse_sexp_at(tokens, i, depth + 1)
            items.push(child)
            i = next
          }
        }
      }
      if !closed {
        raise syntax_error(tok.pos, "unclosed '('")
      }
      (SList(items, tok.pos), i)
    }
    RParen => raise syntax_error(tok.pos, "unexpected ')'")
    Sym => (SAtom(tok.text, tok.pos), start + 1)
    VarTok => (SVar(tok.text, tok.pos), start + 1)
  }
}
