// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// A name collected while reading a typed list.
priv struct PendingName {
  name : String
  mut types : Array[String]
}

///|
fn sexp_pos(node : Sexp) -> Position {
  match node {
    SAtom(_, pos) => pos
    SVar(_, pos) => pos
    SList(_, pos) => pos
  }
}

///|
fn sexp_label(node : Sexp) -> String {
  match node {
    SAtom(text, _) => "'\{text}'"
    SVar(text, _) => "'?\{text}'"
    SList(_, _) => "'('"
  }
}

///|
fn expect_atom(
  node : Sexp,
  what : String,
) -> (String, Position) raise PddlError {
  match node {
    SAtom(text, pos) => (text, pos)
    _ =>
      raise syntax_error(
        sexp_pos(node),
        "expected \{what}, found \{sexp_label(node)}",
      )
  }
}

///|
fn expect_list(
  node : Sexp,
  what : String,
) -> (Array[Sexp], Position) raise PddlError {
  match node {
    SList(items, pos) => (items, pos)
    _ =>
      raise syntax_error(
        sexp_pos(node),
        "expected \{what}, found \{sexp_label(node)}",
      )
  }
}

///|
fn check_duplicates(
  entries : Array[TypedName],
  what : String,
  pos : Position,
) -> Unit raise PddlError {
  let seen : Map[String, Bool] = Map([])
  for entry in entries {
    if seen.contains(entry.name) {
      raise syntax_error(pos, "duplicate \{what} '\{entry.name}'")
    }
    seen.set(entry.name, true)
  }
}

///|
/// Parses a PDDL type annotation after `-`. Returns the type names and the
/// index of the first item after the annotation. A single atom is one type;
/// `(either a b ...)` is a union of types.
fn parse_type_annotation(
  items : ArrayView[Sexp],
  dash_index : Int32,
  context : String,
) -> (Array[String], Int32) raise PddlError {
  let pos = sexp_pos(items[dash_index])
  if dash_index + 1 >= items.length() {
    raise syntax_error(pos, "expected a type name after '-'")
  }
  match items[dash_index + 1] {
    SList(inner, inner_pos) => {
      if inner.length() == 0 {
        raise syntax_error(inner_pos, "empty '(either ...)' in \{context}")
      }
      let (head, _) = expect_atom(inner[0], "'either'")
      if head != "either" {
        raise syntax_error(
          inner_pos,
          "expected a type name or '(either ...)' after '-', found a list starting with '\{head}'",
        )
      }
      if inner.length() < 2 {
        raise syntax_error(
          inner_pos,
          "'(either ...)' needs at least one type in \{context}",
        )
      }
      let types : Array[String] = []
      for i in 1..<inner.length() {
        let (name, name_pos) = expect_atom(
          inner[i],
          "a type name in '(either ...)'",
        )
        if name.get_char(0) == Some(':') {
          raise syntax_error(name_pos, "invalid type name '\{name}'")
        }
        types.push(name)
      }
      (types, dash_index + 2)
    }
    SVar(name, var_pos) =>
      raise syntax_error(
        var_pos,
        "expected a type name after '-', found variable '?\{name}'",
      )
    SAtom(text, atom_pos) => {
      if text.get_char(0) == Some(':') {
        raise syntax_error(atom_pos, "invalid type name '\{text}'")
      }
      ([text], dash_index + 2)
    }
  }
}

///|
/// Parses a PDDL typed list. When `vars` is true the entries must be
/// variables (`?x`); otherwise they must be plain names.
fn parse_typed_list(
  items : ArrayView[Sexp],
  vars : Bool,
  default_type : String,
  context : String,
) -> Array[TypedName] raise PddlError {
  let result : Array[TypedName] = []
  let pending : Array[PendingName] = []
  let mut i = 0
  while i < items.length() {
    match items[i] {
      SAtom(name, pos) =>
        if name == "-" {
          if pending.length() == 0 {
            raise syntax_error(pos, "unexpected '-' in \{context}")
          }
          let (types, next) = parse_type_annotation(items, i, context)
          for entry in pending {
            result.push({ name: entry.name, types: types.copy(), })
          }
          pending.clear()
          i = next
        } else {
          if vars {
            raise syntax_error(
              pos,
              "expected a variable in \{context}, found '\{name}'",
            )
          }
          pending.push({ name, types: [], })
          i += 1
        }
      SVar(name, pos) => {
        if !vars {
          raise syntax_error(
            pos,
            "expected a name in \{context}, found variable '?\{name}'",
          )
        }
        pending.push({ name, types: [], })
        i += 1
      }
      SList(_, pos) =>
        raise syntax_error(pos, "expected a name in \{context}, found '('")
    }
  }
  for entry in pending {
    result.push({ name: entry.name, types: [default_type], })
  }
  result
}

///|
fn supported_requirement(req : String) -> Bool {
  let supported = [
    ":strips", ":typing", ":negative-preconditions", ":disjunctive-preconditions",
    ":equality", ":existential-preconditions", ":universal-preconditions", ":quantified-preconditions",
    ":conditional-effects", ":fluents", ":action-costs", ":adl",
  ]
  supported.contains(req)
}

///|
fn parse_requirements(items : ArrayView[Sexp]) -> Array[String] raise PddlError {
  let result : Array[String] = []
  for item in items {
    let (req, pos) = expect_atom(item, "a requirement keyword")
    if req.get_char(0) != Some(':') {
      raise syntax_error(
        pos,
        "expected a requirement keyword starting with ':', found '\{req}'",
      )
    }
    if !supported_requirement(req) {
      raise unsupported_error(pos, "requirement '\{req}'")
    }
    result.push(req)
  }
  result
}

///|
fn is_reserved_name(name : String) -> Bool {
  let reserved = [
    "and", "or", "not", "imply", "exists", "forall", "either", "=", "<", "<=", ">",
    ">=", "when", "increase", "decrease", "assign", "scale-up", "scale-down",
  ]
  reserved.contains(name)
}

///|
fn push_type_decl(
  result : Array[TypeDecl],
  seen : Map[String, Bool],
  pos : Position,
  name : String,
  parents : Array[String],
) -> Unit raise PddlError {
  if name == "object" {
    raise syntax_error(
      pos, "type 'object' is predefined and cannot be redeclared",
    )
  }
  if name.get_char(0) == Some(':') {
    raise syntax_error(pos, "invalid type name '\{name}'")
  }
  if seen.contains(name) {
    raise syntax_error(pos, "duplicate type '\{name}'")
  }
  seen.set(name, true)
  result.push({
    name,
    parents: if parents.length() > 0 {
      parents.copy()
    } else {
      ["object"]
    },
  })
}

///|
fn parse_type_section(
  items : ArrayView[Sexp],
  pos : Position,
) -> Array[TypeDecl] raise PddlError {
  let result : Array[TypeDecl] = []
  let seen : Map[String, Bool] = Map([])
  let pending : Array[PendingName] = []
  let mut i = 0
  while i < items.length() {
    match items[i] {
      SAtom(name, type_pos) =>
        if name == "-" {
          if pending.length() == 0 {
            raise syntax_error(type_pos, "unexpected '-' in :types")
          }
          let (parents, next) = parse_type_annotation(items, i, ":types")
          for entry in pending {
            entry.types = parents.copy()
          }
          i = next
          for entry in pending {
            push_type_decl(result, seen, pos, entry.name, entry.types)
          }
          pending.clear()
        } else {
          if name.get_char(0) == Some(':') {
            raise syntax_error(type_pos, "invalid type name '\{name}'")
          }
          pending.push({ name, types: [], })
          i += 1
        }
      SVar(name, var_pos) =>
        raise syntax_error(
          var_pos,
          "expected a type name in :types, found variable '?\{name}'",
        )
      SList(_, list_pos) =>
        raise syntax_error(
          list_pos, "expected a type name in :types, found '('",
        )
    }
  }
  for entry in pending {
    push_type_decl(result, seen, pos, entry.name, entry.types)
  }
  let known : Map[String, Bool] = Map([])
  known.set("object", true)
  for decl in result {
    known.set(decl.name, true)
  }
  for decl in result {
    for parent in decl.parents {
      if !known.contains(parent) {
        raise syntax_error(
          pos,
          "unknown supertype '\{parent}' for type '\{decl.name}'",
        )
      }
    }
  }
  let parents : Map[String, Array[String]] = Map([])
  for decl in result {
    parents.set(decl.name, decl.parents)
  }
  for decl in result {
    let queue = decl.parents.copy()
    let visited : Map[String, Bool] = Map([])
    let mut steps = 0
    while queue.length() > 0 && steps <= result.length() + 1 {
      let current = queue.remove(0)
      steps += 1
      if current == decl.name {
        raise syntax_error(
          pos,
          "cyclic type hierarchy involving '\{decl.name}'",
        )
      }
      if visited.contains(current) {
        continue
      }
      visited.set(current, true)
      match parents.get(current) {
        Some(next) =>
          for p in next {
            queue.push(p)
          }
        None => ()
      }
    }
    if steps > result.length() + 1 {
      raise syntax_error(pos, "cyclic type hierarchy involving '\{decl.name}'")
    }
  }
  result
}

///|
fn parse_predicates(
  items : ArrayView[Sexp],
) -> Array[Predicate] raise PddlError {
  let result : Array[Predicate] = []
  let seen : Map[String, Bool] = Map([])
  for item in items {
    let (decl, decl_pos) = expect_list(item, "a predicate declaration")
    if decl.length() == 0 {
      raise syntax_error(decl_pos, "empty predicate declaration")
    }
    let (name, name_pos) = expect_atom(decl[0], "a predicate name")
    if is_reserved_name(name) {
      raise syntax_error(
        name_pos,
        "'\{name}' is reserved and cannot be used as a predicate name",
      )
    }
    if name.get_char(0) == Some(':') {
      raise syntax_error(name_pos, "invalid predicate name '\{name}'")
    }
    if seen.contains(name) {
      raise syntax_error(name_pos, "duplicate predicate '\{name}'")
    }
    seen.set(name, true)
    let params = parse_typed_list(
      decl[1:],
      true,
      "object",
      "predicate '\{name}'",
    )
    check_duplicates(params, "parameter", decl_pos)
    result.push({ name, params, })
  }
  result
}

///|
/// Parses the `:functions` section. Every function returns `number`;
/// the return type annotation is optional and, when present, must be
/// `number` (PDDL `object` fluents are outside the endpoint).
fn parse_functions(
  items : ArrayView[Sexp],
  section_pos : Position,
) -> Array[FunctionDecl] raise PddlError {
  let result : Array[FunctionDecl] = []
  let seen : Map[String, Bool] = Map([])
  let mut i = 0
  while i < items.length() {
    match items[i] {
      SList(decl, decl_pos) => {
        if decl.length() == 0 {
          raise syntax_error(decl_pos, "empty function declaration")
        }
        let (name, name_pos) = expect_atom(decl[0], "a function name")
        if is_reserved_name(name) {
          raise syntax_error(
            name_pos,
            "'\{name}' is reserved and cannot be used as a function name",
          )
        }
        if name.get_char(0) == Some(':') {
          raise syntax_error(name_pos, "invalid function name '\{name}'")
        }
        if seen.contains(name) {
          raise syntax_error(name_pos, "duplicate function '\{name}'")
        }
        seen.set(name, true)
        let params = parse_typed_list(
          decl[1:],
          true,
          "object",
          "function '\{name}'",
        )
        check_duplicates(params, "parameter", decl_pos)
        if name == "total-cost" && params.length() > 0 {
          raise syntax_error(decl_pos, "total-cost must be declared 0-ary")
        }
        result.push({ name, params, })
        i += 1
      }
      SAtom(text, atom_pos) =>
        if text == "-" {
          if result.length() == 0 {
            raise syntax_error(section_pos, "empty ':functions' section")
          }
          if i + 1 >= items.length() {
            raise syntax_error(atom_pos, "expected 'number' after '-'")
          }
          let (ty, ty_pos) = expect_atom(items[i + 1], "'number'")
          if ty != "number" {
            raise unsupported_error(
              ty_pos,
              "function type '\{ty}'; functions must return number (object fluents are not supported)",
            )
          }
          i += 2
        } else {
          raise syntax_error(
            atom_pos,
            "expected a function declaration, found '\{text}'",
          )
        }
      SVar(name, var_pos) =>
        raise syntax_error(
          var_pos,
          "expected a function declaration, found variable '?\{name}'",
        )
    }
  }
  if result.length() == 0 {
    raise syntax_error(section_pos, "empty ':functions' section")
  }
  result
}

///|
fn parse_action(
  section : ArrayView[Sexp],
  pos : Position,
) -> Action raise PddlError {
  if section.length() < 2 {
    raise syntax_error(pos, "expected an action name after ':action'")
  }
  let (name, name_pos) = expect_atom(section[1], "an action name")
  if name.get_char(0) == Some(':') {
    raise syntax_error(
      name_pos,
      "expected an action name, found keyword '\{name}'",
    )
  }
  let mut params : Array[TypedName] = []
  let mut precondition : Formula = And([])
  let mut effect : Effect = AndEffect([])
  let seen : Map[String, Bool] = Map([])
  let mut i = 2
  while i < section.length() {
    let (key, key_pos) = expect_atom(section[i], "an action keyword")
    if i + 1 >= section.length() {
      raise syntax_error(
        key_pos,
        "missing value for '\{key}' in action '\{name}'",
      )
    }
    if seen.contains(key) {
      raise syntax_error(key_pos, "duplicate '\{key}' in action '\{name}'")
    }
    seen.set(key, true)
    if key == ":parameters" {
      let (value, value_pos) = expect_list(section[i + 1], "a parameter list")
      let parsed = parse_typed_list(
        value,
        true,
        "object",
        "action '\{name}' parameters",
      )
      check_duplicates(parsed, "parameter", value_pos)
      params = parsed
    } else if key == ":precondition" {
      precondition = parse_formula(section[i + 1])
    } else if key == ":effect" {
      effect = parse_effect(section[i + 1])
    } else {
      raise unsupported_error(key_pos, "action keyword '\{key}'")
    }
    i += 2
  }
  { name, params, precondition, effect, }
}

///|
/// Parses a PDDL domain.
pub fn parse_domain(source : String) -> Domain raise PddlError {
  let forms = parse_sexps(lex(source))
  if forms.length() == 0 {
    raise syntax_error(
      { line: 1, column: 1, },
      "empty input; expected a (define (domain ...)) form",
    )
  }
  if forms.length() > 1 {
    raise syntax_error(
      sexp_pos(forms[1]),
      "expected exactly one (define ...) form",
    )
  }
  let (top, top_pos) = expect_list(forms[0], "a (define ...) form")
  if top.length() < 2 {
    raise syntax_error(top_pos, "expected (define (domain <name>) ...)")
  }
  let (head, head_pos) = expect_atom(top[0], "'define'")
  if head != "define" {
    raise syntax_error(head_pos, "expected 'define', found '\{head}'")
  }
  let (title, title_pos) = expect_list(top[1], "a (domain <name>) form")
  if title.length() != 2 {
    raise syntax_error(title_pos, "expected (domain <name>)")
  }
  let (kind, kind_pos) = expect_atom(title[0], "'domain'")
  if kind != "domain" {
    raise syntax_error(kind_pos, "expected 'domain', found '\{kind}'")
  }
  let (name, _) = expect_atom(title[1], "a domain name")
  let mut requirements : Array[String] = []
  let mut types : Array[TypeDecl] = []
  let mut constants : Array[TypedName] = []
  let mut predicates : Array[Predicate] = []
  let mut functions : Array[FunctionDecl] = []
  let actions : Array[Action] = []
  let seen_sections : Map[String, Bool] = Map([])
  for idx in 2..<top.length() {
    let (section, section_pos) = expect_list(top[idx], "a domain section")
    if section.length() == 0 {
      raise syntax_error(section_pos, "empty domain section")
    }
    let (key, key_pos) = expect_atom(section[0], "a section keyword")
    if key != ":action" {
      if seen_sections.contains(key) {
        raise syntax_error(key_pos, "duplicate section '\{key}'")
      }
      seen_sections.set(key, true)
    }
    if key == ":requirements" {
      requirements = parse_requirements(section[1:])
    } else if key == ":types" {
      types = parse_type_section(section[1:], key_pos)
    } else if key == ":constants" {
      let parsed = parse_typed_list(section[1:], false, "object", ":constants")
      check_duplicates(parsed, "constant", key_pos)
      constants = parsed
    } else if key == ":predicates" {
      predicates = parse_predicates(section[1:])
    } else if key == ":functions" {
      functions = parse_functions(section[1:], section_pos)
    } else if key == ":action" {
      actions.push(parse_action(section, section_pos))
    } else {
      raise unsupported_error(key_pos, "domain section '\{key}'")
    }
  }
  let action_names : Map[String, Bool] = Map([])
  for action in actions {
    if action_names.contains(action.name) {
      raise syntax_error(top_pos, "duplicate action '\{action.name}'")
    }
    action_names.set(action.name, true)
  }
  { name, requirements, types, constants, predicates, functions, actions, }
}

///|
fn parse_ground_atom(
  items : ArrayView[Sexp],
  pos : Position,
) -> PAtom raise PddlError {
  let atom = parse_atom(items, pos, "init")
  for arg in atom.args {
    match arg {
      Var(name) =>
        raise syntax_error(pos, "variable '?\{name}' is not allowed in :init")
      Const(_) => ()
    }
  }
  atom
}

///|
fn parse_term(node : Sexp, context : String) -> Term raise PddlError {
  match node {
    SAtom(name, _) => Const(name)
    SVar(name, _) => Var(name)
    SList(_, pos) =>
      raise syntax_error(
        pos,
        "expected an object or variable in \{context}, found '('",
      )
  }
}

///|
fn parse_atom(
  items : ArrayView[Sexp],
  pos : Position,
  context : String,
) -> PAtom raise PddlError {
  if items.length() == 0 {
    raise syntax_error(pos, "empty predicate application")
  }
  let (name, name_pos) = expect_atom(items[0], "a predicate name")
  if name.get_char(0) == Some(':') {
    raise syntax_error(
      name_pos,
      "expected a predicate name, found keyword '\{name}'",
    )
  }
  let args : Array[Term] = []
  for i in 1..<items.length() {
    args.push(parse_term(items[i], context))
  }
  { name, args, }
}

///|
/// Parses a number literal: an optional sign, digits and an optional
/// fractional part. Returns `None` when the text is not a number or when it
/// exceeds the supported precision (15 integer digits, 12 fraction digits).
fn parse_number(text : String) -> Double? {
  let chars = text.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut index = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    index = 1
    if chars.length() == 1 {
      return None
    }
  }
  let int_digits : Array[Char] = []
  while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
    int_digits.push(chars[index])
    index += 1
  }
  if int_digits.length() == 0 {
    return None
  }
  if int_digits.length() > 15 {
    return None
  }
  let frac_digits : Array[Char] = []
  if index < chars.length() && chars[index] == '.' {
    index += 1
    while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
      frac_digits.push(chars[index])
      index += 1
    }
    if frac_digits.length() == 0 {
      return None
    }
    if frac_digits.length() > 12 {
      return None
    }
  }
  if index != chars.length() {
    return None
  }
  let mut int_part = 0L
  for c in int_digits {
    int_part = int_part * 10L + Int64::from_int(c.to_int() - 48)
  }
  let mut frac_part = 0L
  for c in frac_digits {
    frac_part = frac_part * 10L + Int64::from_int(c.to_int() - 48)
  }
  let mut scale = 1.0
  let mut digit_index = 0
  while digit_index < frac_digits.length() {
    scale = scale * 10.0
    digit_index += 1
  }
  let mut value = int_part.to_double() + frac_part.to_double() / scale
  if negative {
    value = -value
  }
  Some(value)
}

///|
fn is_numeric_literal(node : Sexp) -> Bool {
  match node {
    SAtom(text, _) => parse_number(text) is Some(_)
    _ => false
  }
}

///|
/// Upper bound on formula, effect and numeric-expression nesting depth.
/// The S-expression reader already bounds nesting at 1024, but semantic
/// recursion frames are larger, so a legal S-expression deep enough could
/// overflow the native stack with no diagnostic. 256 is far beyond any
/// real-world model and safely below the observed crash threshold.
const MAX_FORMULA_DEPTH : Int32 = 256

///|
fn formula_depth_error(pos : Position) -> PddlError {
  syntax_error(pos, "formula nesting exceeds the limit of \{MAX_FORMULA_DEPTH}")
}

///|
/// True when the operand must be read as a numeric expression: any list
/// (function application or arithmetic) or a numeric literal.
fn is_numeric_operand(node : Sexp) -> Bool {
  match node {
    SList(_, _) => true
    other => is_numeric_literal(other)
  }
}

///|
/// Parses a PDDL 2.1 `<f-exp>` numeric expression.
fn parse_num_expr(node : Sexp) -> NumExpr raise PddlError {
  parse_num_expr_at(node, 0)
}

///|
fn parse_num_expr_at(node : Sexp, depth : Int32) -> NumExpr raise PddlError {
  if depth >= MAX_FORMULA_DEPTH {
    raise formula_depth_error(sexp_pos(node))
  }
  match node {
    SAtom(text, _) =>
      match parse_number(text) {
        Some(value) => NumLit(value)
        None => NumFunc({ name: text, args: [], })
      }
    SVar(name, pos) =>
      raise syntax_error(
        pos,
        "variable '?\{name}' cannot appear in a numeric expression",
      )
    SList(items, pos) => {
      if items.length() == 0 {
        raise syntax_error(pos, "empty numeric expression")
      }
      let (head, head_pos) = expect_atom(
        items[0],
        "a numeric operator or function name",
      )
      if head == "+" || head == "*" {
        if items.length() < 3 {
          raise syntax_error(
            head_pos,
            "'\{head}' needs at least two operands in a numeric expression",
          )
        }
        let mut acc = parse_num_expr_at(items[1], depth + 1)
        for i in 2..<items.length() {
          let rhs = parse_num_expr_at(items[i], depth + 1)
          acc = if head == "+" { NumAdd(acc, rhs) } else { NumMul(acc, rhs) }
        }
        acc
      } else if head == "-" {
        if items.length() == 2 {
          NumNeg(parse_num_expr_at(items[1], depth + 1))
        } else if items.length() >= 3 {
          let mut acc = parse_num_expr_at(items[1], depth + 1)
          for i in 2..<items.length() {
            acc = NumSub(acc, parse_num_expr_at(items[i], depth + 1))
          }
          acc
        } else {
          raise syntax_error(
            head_pos, "'-' needs at least one operand in a numeric expression",
          )
        }
      } else if head == "/" {
        if items.length() != 3 {
          raise syntax_error(head_pos, "'/' expects exactly two operands")
        }
        NumDiv(
          parse_num_expr_at(items[1], depth + 1),
          parse_num_expr_at(items[2], depth + 1),
        )
      } else if head == "=" ||
        head == "<" ||
        head == "<=" ||
        head == ">" ||
        head == ">=" {
        raise syntax_error(
          head_pos,
          "comparison '\{head}' cannot appear inside a numeric expression",
        )
      } else {
        NumFunc(parse_atom(items, pos, "numeric expression"))
      }
    }
  }
}

///|
fn compare_op_of(head : String) -> CompareOp {
  match head {
    "<" => CmpLT
    "<=" => CmpLE
    ">" => CmpGT
    ">=" => CmpGE
    _ => CmpEQ
  }
}

///|
fn parse_formula(node : Sexp) -> Formula raise PddlError {
  parse_formula_at(node, 0)
}

///|
fn parse_formula_at(node : Sexp, depth : Int32) -> Formula raise PddlError {
  if depth >= MAX_FORMULA_DEPTH {
    raise formula_depth_error(sexp_pos(node))
  }
  match node {
    SAtom(text, pos) =>
      raise syntax_error(pos, "expected a formula list, found '\{text}'")
    SVar(text, pos) =>
      raise syntax_error(
        pos,
        "expected a formula list, found variable '?\{text}'",
      )
    SList(items, pos) => {
      if items.length() == 0 {
        return And([])
      }
      let (head, head_pos) = expect_atom(items[0], "a formula operator")
      if head == "and" || head == "or" {
        let children : Array[Formula] = []
        for i in 1..<items.length() {
          children.push(parse_formula_at(items[i], depth + 1))
        }
        if head == "and" {
          And(children)
        } else {
          Or(children)
        }
      } else if head == "not" {
        if items.length() != 2 {
          raise syntax_error(head_pos, "'not' expects exactly one formula")
        }
        Not(parse_formula_at(items[1], depth + 1))
      } else if head == "imply" {
        if items.length() != 3 {
          raise syntax_error(head_pos, "'imply' expects exactly two formulas")
        }
        Imply(
          parse_formula_at(items[1], depth + 1),
          parse_formula_at(items[2], depth + 1),
        )
      } else if head == "exists" || head == "forall" {
        if items.length() != 3 {
          raise syntax_error(
            head_pos,
            "'\{head}' expects a variable list and a body",
          )
        }
        let (var_items, var_pos) = expect_list(
          items[1],
          "a typed variable list",
        )
        let vars = parse_typed_list(var_items, true, "object", head)
        if vars.length() == 0 {
          raise syntax_error(
            var_pos,
            "'\{head}' requires at least one variable",
          )
        }
        check_duplicates(vars, "variable", var_pos)
        let body = parse_formula_at(items[2], depth + 1)
        if head == "exists" {
          Exists(vars, body)
        } else {
          Forall(vars, body)
        }
      } else if head == "=" &&
        items.length() == 3 &&
        !is_numeric_operand(items[1]) &&
        !is_numeric_operand(items[2]) {
        Equal(
          parse_term(items[1], "equality"),
          parse_term(items[2], "equality"),
        )
      } else if head == "=" ||
        head == "<" ||
        head == "<=" ||
        head == ">" ||
        head == ">=" {
        if items.length() != 3 {
          raise syntax_error(
            head_pos,
            "'\{head}' expects exactly two expressions",
          )
        }
        Compare(
          compare_op_of(head),
          parse_num_expr(items[1]),
          parse_num_expr(items[2]),
        )
      } else if head == "when" ||
        head == "increase" ||
        head == "decrease" ||
        head == "assign" ||
        head == "scale-up" ||
        head == "scale-down" {
        raise syntax_error(head_pos, "'\{head}' is only allowed in effects")
      } else if head.get_char(0) == Some(':') {
        raise unsupported_error(head_pos, "formula operator '\{head}'")
      } else {
        Atom(parse_atom(items, pos, "formula"))
      }
    }
  }
}

///|
fn parse_numeric_effect(
  items : Array[Sexp],
  head : String,
  pos : Position,
) -> Effect raise PddlError {
  if items.length() != 3 {
    raise syntax_error(
      pos,
      "'\{head}' expects a function term and an expression",
    )
  }
  let fluent : PAtom = match items[1] {
    SAtom(name, _) => { name, args: [], }
    SList(inner, inner_pos) => parse_atom(inner, inner_pos, "numeric effect")
    SVar(name, var_pos) =>
      raise syntax_error(
        var_pos,
        "expected a function term, found variable '?\{name}'",
      )
  }
  let op = match head {
    "increase" => OpIncrease
    "decrease" => OpDecrease
    "assign" => OpAssign
    "scale-up" => OpScaleUp
    _ => OpScaleDown
  }
  NumEffect(op, fluent, parse_num_expr(items[2]))
}

///|
fn parse_effect(node : Sexp) -> Effect raise PddlError {
  parse_effect_at(node, 0)
}

///|
fn parse_effect_at(node : Sexp, depth : Int32) -> Effect raise PddlError {
  if depth >= MAX_FORMULA_DEPTH {
    raise formula_depth_error(sexp_pos(node))
  }
  match node {
    SAtom(text, pos) =>
      raise syntax_error(pos, "expected an effect list, found '\{text}'")
    SVar(text, pos) =>
      raise syntax_error(
        pos,
        "expected an effect list, found variable '?\{text}'",
      )
    SList(items, pos) => {
      if items.length() == 0 {
        return AndEffect([])
      }
      let (head, head_pos) = expect_atom(items[0], "an effect operator")
      if head == "and" {
        let children : Array[Effect] = []
        for i in 1..<items.length() {
          children.push(parse_effect_at(items[i], depth + 1))
        }
        AndEffect(children)
      } else if head == "not" {
        if items.length() != 2 {
          raise syntax_error(head_pos, "'not' expects exactly one predicate")
        }
        let (inner, inner_pos) = expect_list(
          items[1],
          "a predicate application",
        )
        DeleteEffect(parse_atom(inner, inner_pos, "delete effect"))
      } else if head == "forall" {
        if items.length() != 3 {
          raise syntax_error(
            head_pos, "'forall' expects a variable list and a body",
          )
        }
        let (var_items, var_pos) = expect_list(
          items[1],
          "a typed variable list",
        )
        let vars = parse_typed_list(var_items, true, "object", "forall effect")
        if vars.length() == 0 {
          raise syntax_error(var_pos, "'forall' requires at least one variable")
        }
        check_duplicates(vars, "variable", var_pos)
        ForallEffect(vars, parse_effect_at(items[2], depth + 1))
      } else if head == "when" {
        if items.length() != 3 {
          raise syntax_error(
            head_pos, "'when' expects a condition and an effect",
          )
        }
        WhenEffect(
          parse_formula(items[1]),
          parse_effect_at(items[2], depth + 1),
        )
      } else if head == "increase" ||
        head == "decrease" ||
        head == "assign" ||
        head == "scale-up" ||
        head == "scale-down" {
        parse_numeric_effect(items, head, head_pos)
      } else if head == "or" || head == "exists" {
        raise syntax_error(head_pos, "'\{head}' is not allowed in effects")
      } else if head == "=" {
        raise unsupported_error(head_pos, "equality in effects")
      } else if head == "<" || head == "<=" || head == ">" || head == ">=" {
        raise syntax_error(
          head_pos,
          "comparison '\{head}' is not allowed in effects",
        )
      } else if head.get_char(0) == Some(':') {
        raise unsupported_error(head_pos, "effect operator '\{head}'")
      } else {
        AddEffect(parse_atom(items, pos, "effect"))
      }
    }
  }
}

///|
fn parse_init_func_app(node : Sexp, context : String) -> PAtom raise PddlError {
  match node {
    SAtom(name, pos) => {
      if name.get_char(0) == Some(':') {
        raise syntax_error(
          pos,
          "expected a function name, found keyword '\{name}'",
        )
      }
      { name, args: [], }
    }
    SList(inner, pos) => {
      let atom = parse_atom(inner, pos, context)
      for arg in atom.args {
        match arg {
          Var(name) =>
            raise syntax_error(
              pos,
              "variable '?\{name}' is not allowed in \{context}",
            )
          Const(_) => ()
        }
      }
      atom
    }
    SVar(name, var_pos) =>
      raise syntax_error(
        var_pos,
        "expected a function term in \{context}, found variable '?\{name}'",
      )
  }
}

///|
fn parse_init_elem(node : Sexp) -> InitElem raise PddlError {
  let (items, pos) = expect_list(node, "an init element")
  if items.length() == 0 {
    raise syntax_error(pos, "empty init element")
  }
  let (head, head_pos) = expect_atom(items[0], "a predicate name")
  if head == "=" {
    if items.length() != 3 {
      raise syntax_error(pos, "expected (= (<function> ...) <number>)")
    }
    let fluent = parse_init_func_app(items[1], ":init")
    let (value_text, value_pos) = expect_atom(items[2], "a number")
    match parse_number(value_text) {
      Some(value) => InitFunc(fluent, value)
      None =>
        raise syntax_error(
          value_pos,
          "expected a number, found '\{value_text}'",
        )
    }
  } else if head == "not" {
    raise unsupported_error(
      head_pos, "negated init literals; PDDL :init is a positive closed-world state",
    )
  } else if head == "increase" ||
    head == "decrease" ||
    head == "assign" ||
    head == "scale-up" ||
    head == "scale-down" {
    raise syntax_error(
      head_pos, "numeric effects are not allowed in :init; assign a value with (= (<function> ...) <number>)",
    )
  } else if head.get_char(0) == Some(':') {
    raise syntax_error(
      head_pos,
      "expected a predicate name, found keyword '\{head}'",
    )
  } else {
    InitFact(parse_ground_atom(items, pos))
  }
}

///|
fn parse_metric(
  items : ArrayView[Sexp],
  pos : Position,
) -> Metric raise PddlError {
  if items.length() != 2 {
    raise syntax_error(pos, "':metric' expects a direction and an expression")
  }
  let (direction, direction_pos) = expect_atom(
    items[0],
    "'minimize' or 'maximize'",
  )
  let dir = match direction {
    "minimize" => Minimize
    "maximize" => Maximize
    _ =>
      raise unsupported_error(
        direction_pos,
        "metric direction '\{direction}'; only minimize and maximize are supported",
      )
  }
  Metric(dir, parse_num_expr(items[1]))
}

///|
/// Parses a PDDL problem instance.
pub fn parse_problem(source : String) -> Problem raise PddlError {
  let forms = parse_sexps(lex(source))
  if forms.length() == 0 {
    raise syntax_error(
      { line: 1, column: 1, },
      "empty input; expected a (define (problem ...)) form",
    )
  }
  if forms.length() > 1 {
    raise syntax_error(
      sexp_pos(forms[1]),
      "expected exactly one (define ...) form",
    )
  }
  let (top, top_pos) = expect_list(forms[0], "a (define ...) form")
  if top.length() < 2 {
    raise syntax_error(top_pos, "expected (define (problem <name>) ...)")
  }
  let (head, head_pos) = expect_atom(top[0], "'define'")
  if head != "define" {
    raise syntax_error(head_pos, "expected 'define', found '\{head}'")
  }
  let (title, title_pos) = expect_list(top[1], "a (problem <name>) form")
  if title.length() != 2 {
    raise syntax_error(title_pos, "expected (problem <name>)")
  }
  let (kind, kind_pos) = expect_atom(title[0], "'problem'")
  if kind != "problem" {
    raise syntax_error(kind_pos, "expected 'problem', found '\{kind}'")
  }
  let (name, _) = expect_atom(title[1], "a problem name")
  let mut domain_name = ""
  let mut has_domain = false
  let mut requirements : Array[String] = []
  let mut objects : Array[TypedName] = []
  let init : Array[InitElem] = []
  let mut goal : Formula? = None
  let mut metric : Metric? = None
  let seen_sections : Map[String, Bool] = Map([])
  for idx in 2..<top.length() {
    let (section, section_pos) = expect_list(top[idx], "a problem section")
    if section.length() == 0 {
      raise syntax_error(section_pos, "empty problem section")
    }
    let (key, key_pos) = expect_atom(section[0], "a section keyword")
    if seen_sections.contains(key) {
      raise syntax_error(key_pos, "duplicate section '\{key}'")
    }
    seen_sections.set(key, true)
    if key == ":domain" {
      if section.length() != 2 {
        raise syntax_error(key_pos, "':domain' expects exactly one name")
      }
      let (parsed, _) = expect_atom(section[1], "a domain name")
      domain_name = parsed
      has_domain = true
    } else if key == ":requirements" {
      requirements = parse_requirements(section[1:])
    } else if key == ":objects" {
      let parsed = parse_typed_list(section[1:], false, "object", ":objects")
      check_duplicates(parsed, "object", key_pos)
      objects = parsed
    } else if key == ":init" {
      for item in section[1:] {
        init.push(parse_init_elem(item))
      }
    } else if key == ":goal" {
      if section.length() != 2 {
        raise syntax_error(key_pos, "':goal' expects exactly one formula")
      }
      goal = Some(parse_formula(section[1]))
    } else if key == ":metric" {
      metric = Some(parse_metric(section[1:], key_pos))
    } else {
      raise unsupported_error(key_pos, "problem section '\{key}'")
    }
  }
  if !has_domain {
    raise syntax_error(top_pos, "problem is missing a (:domain <name>) section")
  }
  let final_goal = match goal {
    Some(parsed) => parsed
    None =>
      raise syntax_error(top_pos, "problem is missing a (:goal ...) section")
  }
  { name, domain_name, requirements, objects, init, goal: final_goal, metric, }
}
