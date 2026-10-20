// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// A 1-based source position inside a PDDL document.
pub(all) struct Position {
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// Structured description of a PDDL parse or model error.
pub(all) enum PddlErrorData {
  /// The input is not syntactically valid PDDL.
  SyntaxError(Position, String)
  /// The construct is valid PDDL but outside the supported subset.
  Unsupported(Position, String)
  /// The domain and problem are syntactically valid but inconsistent or
  /// outside the supported semantics.
  InvalidModel(String)
} derive(Eq, Debug)

///|
/// The single error type raised by all PDDL front-end entry points.
pub suberror PddlError {
  PddlError(PddlErrorData)
} derive(Debug)

///|
fn PddlErrorData::message(self : PddlErrorData) -> String {
  match self {
    SyntaxError(pos, msg) => "line \{pos.line}, column \{pos.column}: \{msg}"
    Unsupported(pos, msg) =>
      "line \{pos.line}, column \{pos.column}: unsupported: \{msg}"
    InvalidModel(msg) => "invalid model: \{msg}"
  }
}

///|
/// A human readable description including the source position.
pub fn PddlError::message(self : PddlError) -> String {
  match self {
    PddlError(data) => data.message()
  }
}

///|
pub impl Show for PddlError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
fn syntax_error(pos : Position, msg : String) -> PddlError {
  PddlError(SyntaxError(pos, msg))
}

///|
fn unsupported_error(pos : Position, msg : String) -> PddlError {
  PddlError(Unsupported(pos, msg))
}

///|
fn model_error(msg : String) -> PddlError {
  PddlError(InvalidModel(msg))
}
