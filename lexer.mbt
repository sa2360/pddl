// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// Token kind produced by the PDDL lexer.
priv enum TokenKind {
  LParen
  RParen
  Sym
  VarTok
}

///|
priv struct Token {
  kind : TokenKind
  text : String
  pos : Position
}

///|
/// Character cursor with line/column tracking. PDDL is ASCII in practice;
/// `String::to_array` gives code-point indexing, which is all we need.
priv struct Lexer {
  chars : Array[Char]
  mut i : Int
  mut line : Int
  mut col : Int
}

///|
fn Lexer::make(source : String) -> Lexer {
  { chars: source.to_array(), i: 0, line: 1, col: 1, }
}

///|
fn Lexer::at_end(self : Lexer) -> Bool {
  self.i >= self.chars.length()
}

///|
fn Lexer::here(self : Lexer) -> Position {
  { line: self.line, column: self.col, }
}

///|
fn Lexer::advance(self : Lexer) -> Char {
  let c = self.chars[self.i]
  self.i += 1
  if c == '\n' {
    self.line += 1
    self.col = 1
  } else {
    self.col += 1
  }
  c
}

///|
fn is_symbol_char(c : Char) -> Bool {
  !(c == '(' || c == ')' || c == ';' || c == '?' || c.is_whitespace())
}

///|
fn Lexer::skip_trivia(self : Lexer) -> Unit {
  while !self.at_end() {
    let c = self.chars[self.i]
    if c.is_whitespace() {
      ignore(self.advance())
    } else if c == ';' {
      while !self.at_end() && self.chars[self.i] != '\n' {
        ignore(self.advance())
      }
    } else {
      break
    }
  }
}

///|
fn Lexer::read_symbol(self : Lexer) -> String {
  let sb = StringBuilder::StringBuilder()
  while !self.at_end() && is_symbol_char(self.chars[self.i]) {
    sb.write_char(self.advance().to_ascii_lowercase())
  }
  sb.to_string()
}

///|
/// Splits a PDDL source into tokens. Symbols are normalized to lowercase,
/// comments (`;` to end of line) and whitespace are dropped.
fn lex(source : String) -> Array[Token] raise PddlError {
  let lx = Lexer::make(source)
  let tokens : Array[Token] = []
  while true {
    lx.skip_trivia()
    if lx.at_end() {
      break
    }
    let pos = lx.here()
    let c = lx.chars[lx.i]
    if c == '(' {
      ignore(lx.advance())
      tokens.push({ kind: LParen, text: "(", pos, })
    } else if c == ')' {
      ignore(lx.advance())
      tokens.push({ kind: RParen, text: ")", pos, })
    } else if c == '?' {
      ignore(lx.advance())
      let name = lx.read_symbol()
      if name == "" {
        raise syntax_error(lx.here(), "expected a variable name after '?'")
      }
      tokens.push({ kind: VarTok, text: name, pos, })
    } else {
      let text = lx.read_symbol()
      if text == "" {
        raise syntax_error(pos, "unexpected character '\{c}'")
      }
      tokens.push({ kind: Sym, text, pos, })
    }
  }
  tokens
}
