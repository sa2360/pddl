// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
/// A name collected while reading a typed list.
priv struct PendingName {
  name : String
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
          if i + 1 >= items.length() {
            raise syntax_error(pos, "expected a type name after '-'")
          }
          let (parent, _) = expect_atom(items[i + 1], "a type name")
          for entry in pending {
            result.push({ name: entry.name, type_name: parent, })
          }
          pending.clear()
          i += 2
        } else {
          if vars {
            raise syntax_error(
              pos,
              "expected a variable in \{context}, found '\{name}'",
            )
          }
          pending.push({ name, })
          i += 1
        }
      SVar(name, pos) => {
        if !vars {
          raise syntax_error(
            pos,
            "expected a name in \{context}, found variable '?\{name}'",
          )
        }
        pending.push({ name, })
        i += 1
      }
      SList(_, pos) =>
        raise syntax_error(pos, "expected a name in \{context}, found '('")
    }
  }
  for entry in pending {
    result.push({ name: entry.name, type_name: default_type, })
  }
  result
}

///|
fn supported_requirement(req : String) -> Bool {
  let supported = [
    ":strips", ":typing", ":negative-preconditions", ":disjunctive-preconditions",
    ":equality", ":existential-preconditions", ":universal-preconditions", ":quantified-preconditions",
    ":conditional-effects", ":action-costs", ":adl",
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
fn parse_type_section(
  items : ArrayView[Sexp],
  pos : Position,
) -> Array[TypeDecl] raise PddlError {
  let typed = parse_typed_list(items, false, "object", ":types")
  let result : Array[TypeDecl] = []
  let seen : Map[String, Bool] = Map([])
  for entry in typed {
    if entry.name == "object" {
      raise syntax_error(
        pos, "type 'object' is predefined and cannot be redeclared",
      )
    }
    if entry.name.get_char(0) == Some(':') {
      raise syntax_error(pos, "invalid type name '\{entry.name}'")
    }
    if seen.contains(entry.name) {
      raise syntax_error(pos, "duplicate type '\{entry.name}'")
    }
    seen.set(entry.name, true)
    result.push({ name: entry.name, parent: entry.type_name, })
  }
  let known : Map[String, Bool] = Map([])
  known.set("object", true)
  for decl in result {
    known.set(decl.name, true)
  }
  for decl in result {
    if !known.contains(decl.parent) {
      raise syntax_error(
        pos,
        "unknown supertype '\{decl.parent}' for type '\{decl.name}'",
      )
    }
  }
  let parents : Map[String, String] = Map([])
  for decl in result {
    parents.set(decl.name, decl.parent)
  }
  for decl in result {
    let mut cur = decl.parent
    let mut steps = 0
    while cur != "object" && steps <= result.length() {
      if cur == decl.name {
        raise syntax_error(
          pos,
          "cyclic type hierarchy involving '\{decl.name}'",
        )
      }
      cur = match parents.get(cur) {
        Some(parent) => parent
        None => "object"
      }
      steps += 1
    }
    if steps > result.length() {
      raise syntax_error(pos, "cyclic type hierarchy involving '\{decl.name}'")
    }
  }
  result
}

///|
fn is_reserved_formula_word(name : String) -> Bool {
  let reserved = [
    "and", "or", "not", "imply", "exists", "forall", "=", "when", "increase", "decrease",
    "assign", "scale-up", "scale-down",
  ]
  reserved.contains(name)
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
    if name == "=" || is_reserved_formula_word(name) {
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
        if name != "total-cost" {
          raise unsupported_error(
            name_pos,
            "function '\{name}'; only the 0-ary total-cost function is supported",
          )
        }
        if decl.length() != 1 {
          raise unsupported_error(
            decl_pos, "arguments on total-cost; it must be 0-ary",
          )
        }
        if seen.contains(name) {
          raise syntax_error(name_pos, "duplicate function '\{name}'")
        }
        seen.set(name, true)
        result.push({ name: "total-cost", params: [], })
        i += 1
      }
      SAtom(text, atom_pos) =>
        if text == "-" {
          if i + 1 >= items.length() {
            raise syntax_error(atom_pos, "expected 'number' after '-'")
          }
          let (ty, ty_pos) = expect_atom(items[i + 1], "'number'")
          if ty != "number" {
            raise unsupported_error(
              ty_pos,
              "function type '\{ty}'; only :number is supported",
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
      raise unsupported_error(
        pos,
        "function term in \{context}; numeric fluents other than total-cost are not supported",
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
fn parse_formula(node : Sexp) -> Formula raise PddlError {
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
          children.push(parse_formula(items[i]))
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
        Not(parse_formula(items[1]))
      } else if head == "imply" {
        if items.length() != 3 {
          raise syntax_error(head_pos, "'imply' expects exactly two formulas")
        }
        Imply(parse_formula(items[1]), parse_formula(items[2]))
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
        let body = parse_formula(items[2])
        if head == "exists" {
          Exists(vars, body)
        } else {
          Forall(vars, body)
        }
      } else if head == "=" {
        if items.length() != 3 {
          raise syntax_error(head_pos, "'=' expects exactly two terms")
        }
        Equal(
          parse_term(items[1], "equality"),
          parse_term(items[2], "equality"),
        )
      } else if head == "when" || head == "increase" {
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
fn parse_increase(
  items : Array[Sexp],
  pos : Position,
) -> Effect raise PddlError {
  if items.length() != 3 {
    raise syntax_error(pos, "'increase' expects a function term and an amount")
  }
  let fname = match items[1] {
    SAtom(name, _) => name
    SList(inner, list_pos) => {
      if inner.length() != 1 {
        raise unsupported_error(list_pos, "function term in increase")
      }
      let (name, _) = expect_atom(inner[0], "a function name")
      name
    }
    SVar(name, var_pos) =>
      raise syntax_error(
        var_pos,
        "expected a function term, found variable '?\{name}'",
      )
  }
  if fname != "total-cost" {
    raise unsupported_error(
      pos,
      "numeric fluent '\{fname}'; only total-cost is supported",
    )
  }
  let (amount_text, amount_pos) = expect_atom(
    items[2],
    "a non-negative integer",
  )
  match parse_int(amount_text) {
    Some(amount) => IncreaseEffect("total-cost", amount)
    None =>
      raise syntax_error(
        amount_pos,
        "expected a non-negative integer, found '\{amount_text}'",
      )
  }
}

///|
fn parse_effect(node : Sexp) -> Effect raise PddlError {
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
          children.push(parse_effect(items[i]))
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
        ForallEffect(vars, parse_effect(items[2]))
      } else if head == "when" {
        if items.length() != 3 {
          raise syntax_error(
            head_pos, "'when' expects a condition and an effect",
          )
        }
        WhenEffect(parse_formula(items[1]), parse_effect(items[2]))
      } else if head == "increase" {
        parse_increase(items, head_pos)
      } else if head == "decrease" ||
        head == "assign" ||
        head == "scale-up" ||
        head == "scale-down" {
        raise unsupported_error(
          head_pos,
          "numeric effect '\{head}'; only (increase (total-cost) N) is supported",
        )
      } else if head == "or" || head == "exists" {
        raise syntax_error(head_pos, "'\{head}' is not allowed in effects")
      } else if head == "=" {
        raise unsupported_error(head_pos, "equality in effects")
      } else if head.get_char(0) == Some(':') {
        raise unsupported_error(head_pos, "effect operator '\{head}'")
      } else {
        AddEffect(parse_atom(items, pos, "effect"))
      }
    }
  }
}

///|
fn parse_int(text : String) -> Int64? {
  if text == "" {
    return None
  }
  let mut value = 0L
  for c in text.to_array() {
    if c < '0' || c > '9' {
      return None
    }
    let digit = Int64::from_int(c.to_int() - 48)
    if value > (MAX_COST_VALUE - digit) / 10L {
      return None
    }
    value = value * 10L + digit
  }
  Some(value)
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
      raise syntax_error(pos, "expected (= (total-cost) <number>)")
    }
    let (lhs, lhs_pos) = expect_list(items[1], "a function term")
    if lhs.length() != 1 {
      raise unsupported_error(
        lhs_pos, "function term in :init; only (total-cost) is supported",
      )
    }
    let (fname, fname_pos) = expect_atom(lhs[0], "'total-cost'")
    if fname != "total-cost" {
      raise unsupported_error(fname_pos, "numeric fluent '\{fname}' in :init")
    }
    let (value_text, value_pos) = expect_atom(
      items[2],
      "a non-negative integer",
    )
    match parse_int(value_text) {
      Some(value) => InitCost(value)
      None =>
        raise syntax_error(
          value_pos,
          "expected a non-negative integer, found '\{value_text}'",
        )
    }
  } else if head == "not" {
    raise unsupported_error(
      head_pos, "negated init literals; PDDL :init is a positive closed-world state",
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
  let (direction, direction_pos) = expect_atom(items[0], "'minimize'")
  if direction != "minimize" {
    raise unsupported_error(
      direction_pos,
      "metric direction '\{direction}'; only minimize is supported",
    )
  }
  let target_ok = match items[1] {
    SAtom(name, _) => name == "total-cost"
    SList(inner, _) =>
      if inner.length() == 1 {
        match inner[0] {
          SAtom(name, _) => name == "total-cost"
          _ => false
        }
      } else {
        false
      }
    SVar(_, _) => false
  }
  if !target_ok {
    raise unsupported_error(
      pos, "metric expression; only (minimize (total-cost)) is supported",
    )
  }
  MinimizeTotalCost
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
