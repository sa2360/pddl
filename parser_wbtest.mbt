// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
test "parse blocksworld domain" {
  let domain = parse_domain(blocksworld_domain)
  @test.assert_eq(domain.name, "blocksworld")
  @test.assert_eq(domain.requirements, [":strips", ":typing"])
  @test.assert_eq(domain.types.length(), 1)
  @test.assert_eq(domain.types[0].name, "block")
  @test.assert_eq(domain.types[0].parents, ["object"])
  @test.assert_eq(domain.predicates.length(), 5)
  @test.assert_eq(domain.actions.length(), 4)
  let pick_up = domain.actions[0]
  @test.assert_eq(pick_up.name, "pick-up")
  @test.assert_eq(pick_up.params.length(), 1)
  @test.assert_eq(pick_up.params[0].name, "x")
  @test.assert_eq(pick_up.params[0].types, ["block"])
  match pick_up.effect {
    AndEffect(effects) => {
      @test.assert_eq(effects.length(), 4)
      match effects[0] {
        DeleteEffect(atom) => @test.assert_eq(atom.name, "ontable")
        _ => abort("expected a delete effect")
      }
    }
    _ => abort("expected a conjunction effect")
  }
}

///|
test "parse blocksworld problem" {
  let problem = parse_problem(blocksworld_problem)
  @test.assert_eq(problem.name, "blocks-3")
  @test.assert_eq(problem.domain_name, "blocksworld")
  @test.assert_eq(problem.objects.length(), 3)
  @test.assert_eq(problem.objects[1].name, "b")
  @test.assert_eq(problem.init.length(), 7)
  match problem.goal {
    And(goals) => {
      @test.assert_eq(goals.length(), 2)
      match goals[0] {
        Atom(atom) => {
          @test.assert_eq(atom.name, "on")
          @test.assert_eq(atom.args.length(), 2)
        }
        _ => abort("expected an atom goal")
      }
    }
    _ => abort("expected a conjunction goal")
  }
  match problem.metric {
    None => ()
    Some(_) => abort("expected no metric")
  }
}

///|
test "lexer is case-insensitive and skips comments" {
  let source =
    #|(DEFINE (DOMAIN Demo)
    #|  ; a comment
    #|  (:TYPES BLOCK)
    #|  (:PREDICATES (P ?X - BLOCK))
    #|  (:ACTION A
    #|    :PARAMETERS (?X - BLOCK)
    #|    :PRECONDITION (P ?X)
    #|    :EFFECT (P ?X)))
  let domain = parse_domain(source)
  @test.assert_eq(domain.name, "demo")
  @test.assert_eq(domain.types[0].name, "block")
  @test.assert_eq(domain.actions[0].name, "a")
  @test.assert_eq(domain.actions[0].params[0].name, "x")
}

///|
test "typed lists group names before '-'" {
  let source =
    #|(define (domain transport)
    #|  (:types truck car - vehicle vehicle - object)
    #|  (:constants depot - location t1 t2 - truck)
    #|  (:predicates (at ?t - truck ?l - location)))
  let domain = parse_domain(source)
  @test.assert_eq(domain.types.length(), 3)
  @test.assert_eq(domain.types[0].parents, ["vehicle"])
  @test.assert_eq(domain.types[1].parents, ["vehicle"])
  @test.assert_eq(domain.types[2].parents, ["object"])
  @test.assert_eq(domain.constants.length(), 3)
  @test.assert_eq(domain.constants[1].name, "t1")
  @test.assert_eq(domain.constants[1].types, ["truck"])
}

///|
test "parse conditional effects and action cost" {
  let source =
    #|(define (domain transit)
    #|  (:requirements :strips :typing :conditional-effects :action-costs)
    #|  (:types location vehicle package)
    #|  (:predicates
    #|    (at ?v - vehicle ?l - location)
    #|    (in ?p - package ?v - vehicle)
    #|    (delivered ?p - package))
    #|  (:functions (total-cost) - number)
    #|  (:action load
    #|    :parameters (?p - package ?v - vehicle ?l - location)
    #|    :precondition (and (at ?v ?l) (not (in ?p ?v)))
    #|    :effect (and (in ?p ?v) (increase (total-cost) 2))))
  let domain = parse_domain(source)
  @test.assert_eq(domain.functions.length(), 1)
  let action = domain.actions[0]
  match action.precondition {
    And(parts) => {
      @test.assert_eq(parts.length(), 2)
      match parts[1] {
        Not(inner) =>
          match inner {
            Atom(atom) => @test.assert_eq(atom.name, "in")
            _ => abort("expected an atom under not")
          }
        _ => abort("expected a negated precondition")
      }
    }
    _ => abort("expected a conjunction precondition")
  }
  match action.effect {
    AndEffect(parts) => {
      @test.assert_eq(parts.length(), 2)
      match parts[1] {
        NumEffect(OpIncrease, fluent, expr) => {
          @test.assert_eq(fluent.name, "total-cost")
          @test.assert_eq(expr, NumLit(2.0))
        }
        _ => abort("expected an increase effect")
      }
    }
    _ => abort("expected a conjunction effect")
  }
}

///|
test "parse quantified precondition and metric" {
  let source =
    #|(define (domain forall-demo)
    #|  (:types block)
    #|  (:predicates (clear ?b - block))
    #|  (:action clear-all
    #|    :parameters ()
    #|    :precondition (forall (?b - block) (clear ?b))
    #|    :effect (and)))
  let domain = parse_domain(source)
  match domain.actions[0].precondition {
    Forall(vars, _) => {
      @test.assert_eq(vars.length(), 1)
      @test.assert_eq(vars[0].name, "b")
      @test.assert_eq(vars[0].types, ["block"])
    }
    _ => abort("expected a forall precondition")
  }
  let problem_source =
    #|(define (problem p)
    #|  (:domain forall-demo)
    #|  (:objects a b - block)
    #|  (:init (clear a) (clear b) (= (total-cost) 0))
    #|  (:goal (and (clear a) (clear b)))
    #|  (:metric minimize total-cost))
  let problem = parse_problem(problem_source)
  @test.assert_eq(problem.init.length(), 3)
  match problem.init[2] {
    InitFunc(atom, value) => {
      @test.assert_eq(atom.name, "total-cost")
      @test.assert_eq(value, 0.0)
    }
    _ => abort("expected an init function assignment")
  }
  match problem.metric {
    Some(Metric(Minimize, _)) => ()
    _ => abort("expected a minimize metric")
  }
}

///|
test "parse functions with parameters and comparisons" {
  let source =
    #|(define (domain numeric)
    #|  (:requirements :typing :fluents :action-costs)
    #|  (:types place vehicle)
    #|  (:predicates (at ?v - vehicle ?p - place))
    #|  (:functions
    #|    (fuel ?v - vehicle) - number
    #|    (distance ?a - place ?b - place) - number
    #|    (price) - number
    #|    (total-cost) - number)
    #|  (:action drive
    #|    :parameters (?v - vehicle ?from - place ?to - place)
    #|    :precondition (and (at ?v ?from) (>= (fuel ?v) (* 2 (distance ?from ?to))))
    #|    :effect (and (decrease (fuel ?v) (distance ?from ?to))
    #|                 (increase (total-cost) (+ (price) 1.5)))))
  let domain = parse_domain(source)
  @test.assert_eq(domain.functions.length(), 4)
  @test.assert_eq(domain.functions[0].name, "fuel")
  @test.assert_eq(domain.functions[0].params.length(), 1)
  @test.assert_eq(domain.functions[1].params[0].types, ["place"])
  let action = domain.actions[0]
  match action.precondition {
    And(parts) =>
      match parts[1] {
        Compare(CmpGE, lhs, rhs) => {
          @test.assert_eq(lhs, NumFunc({ name: "fuel", args: [Var("v")], }))
          match rhs {
            NumMul(_, _) => ()
            _ => abort("expected a multiplication on the right-hand side")
          }
        }
        _ => abort("expected a numeric comparison")
      }
    _ => abort("expected a conjunction precondition")
  }
  match action.effect {
    AndEffect(parts) => {
      match parts[0] {
        NumEffect(OpDecrease, fluent, _) => @test.assert_eq(fluent.name, "fuel")
        _ => abort("expected a decrease effect")
      }
      match parts[1] {
        NumEffect(OpIncrease, _, expr) =>
          match expr {
            NumAdd(NumFunc(f), NumLit(value)) => {
              @test.assert_eq(f.name, "price")
              @test.assert_eq(value, 1.5)
            }
            _ => abort("expected an addition with a real literal")
          }
        _ => abort("expected an increase effect")
      }
    }
    _ => abort("expected a conjunction effect")
  }
}

///|
test "parse metric maximize and negative real init values" {
  let source =
    #|(define (problem p)
    #|  (:domain delivery-numeric)
    #|  (:objects a - place t1 - truck)
    #|  (:init (= (fuel t1) -2.5))
    #|  (:goal (visited a))
    #|  (:metric maximize (+ (fuel t1) 3)))
  let problem = parse_problem(source)
  match problem.init[0] {
    InitFunc(atom, value) => {
      @test.assert_eq(atom.name, "fuel")
      @test.assert_eq(value, -2.5)
    }
    _ => abort("expected an init function assignment")
  }
  match problem.metric {
    Some(Metric(Maximize, expr)) =>
      match expr {
        NumAdd(_, _) => ()
        _ => abort("expected an addition in the metric")
      }
    _ => abort("expected a maximize metric")
  }
}

///|
test "parse either types" {
  let domain = parse_domain(either_domain)
  @test.assert_eq(domain.types.length(), 3)
  let action = domain.actions[0]
  @test.assert_eq(action.params[0].types, ["block", "ball"])
  @test.assert_eq(domain.predicates[0].params[0].types, ["block", "ball"])
  let problem = parse_problem(either_problem)
  @test.assert_eq(problem.objects.length(), 3)
}

///|
test "parse numeric effect operators" {
  let source =
    #|(define (domain ops)
    #|  (:requirements :fluents)
    #|  (:functions (f ?x) - number (g) - number)
    #|  (:action a
    #|    :parameters (?x)
    #|    :precondition ()
    #|    :effect (and (assign (f ?x) (/ (g) 2))
    #|                 (scale-up (f ?x) 3)
    #|                 (scale-down (f ?x) 0.5)
    #|                 (decrease (g) -1))))
  let domain = parse_domain(source)
  match domain.actions[0].effect {
    AndEffect(parts) => {
      @test.assert_eq(parts.length(), 4)
      match parts[0] {
        NumEffect(OpAssign, fluent, NumDiv(NumFunc(_), NumLit(_))) =>
          @test.assert_eq(fluent.name, "f")
        _ => abort("expected an assign with division")
      }
      match parts[1] {
        NumEffect(OpScaleUp, _, NumLit(v)) => @test.assert_eq(v, 3.0)
        _ => abort("expected a scale-up")
      }
      match parts[2] {
        NumEffect(OpScaleDown, _, NumLit(v)) => @test.assert_eq(v, 0.5)
        _ => abort("expected a scale-down")
      }
      match parts[3] {
        NumEffect(OpDecrease, fluent, NumLit(v)) => {
          @test.assert_eq(fluent.name, "g")
          @test.assert_eq(v, -1.0)
        }
        _ => abort("expected a decrease")
      }
    }
    _ => abort("expected a conjunction effect")
  }
}

///|
test "error: unclosed parenthesis" {
  let err = try {
    ignore(parse_domain("(define (domain d)"))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("unclosed"), true)
  @test.assert_eq(err.message().contains("line 1"), true)
}

///|
test "error: unsupported requirement" {
  let err = try {
    ignore(
      parse_domain("(define (domain d) (:requirements :durative-actions))"),
    )
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("unsupported"), true)
  @test.assert_eq(err.message().contains(":durative-actions"), true)
}

///|
test "error: unknown supertype" {
  let err = try {
    ignore(parse_domain("(define (domain d) (:types block - unknown))"))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("unknown supertype"), true)
}

///|
test "error: duplicate action" {
  let source =
    #|(define (domain d)
    #|  (:action a)
    #|  (:action a))
  let err = try {
    ignore(parse_domain(source))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("duplicate action"), true)
}

///|
test "error: missing goal" {
  let err = try {
    ignore(parse_problem("(define (problem p) (:domain d) (:objects a))"))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("(:goal"), true)
}

///|
test "error: variable in init" {
  let err = try {
    ignore(
      parse_problem(
        "(define (problem p) (:domain d) (:init (at ?x)) (:goal (ready)))",
      ),
    )
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("variable"), true)
}

///|
test "error: missing action keyword value" {
  let err = try {
    ignore(parse_domain("(define (domain d) (:action a :parameters))"))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("missing value"), true)
}

///|
test "error: effect keyword used as a predicate name" {
  let err = try {
    ignore(parse_domain("(define (domain d) (:predicates (when) (increase)))"))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("reserved"), true)
  @test.assert_eq(err.message().contains("when"), true)
}

///|
test "error: duplicate function declaration" {
  let err = try {
    ignore(
      parse_domain("(define (domain d) (:functions (total-cost) (total-cost)))"),
    )
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("duplicate function"), true)
}

///|
test "error: empty functions section" {
  let err = try {
    ignore(parse_domain("(define (domain d) (:functions - number))"))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("empty ':functions'"), true)
}

///|
test "error: object-fluent return type" {
  let err = try {
    ignore(parse_domain("(define (domain d) (:functions (f) - location))"))
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(err.message().contains("must return number"), true)
}

///|
test "error: variable in a numeric expression" {
  let err = try {
    ignore(
      parse_domain(
        "(define (domain d) (:action a :parameters (?x) :precondition (>= ?x 3) :effect (and)))",
      ),
    )
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(
    err.message().contains("cannot appear in a numeric expression"),
    true,
  )
}

///|
test "error: comparison inside a numeric expression" {
  let err = try {
    ignore(
      parse_domain(
        "(define (domain d) (:functions (f) - number) (:action a :parameters () :precondition (>= (+ (< (f) 3) 1) 0) :effect (and)))",
      ),
    )
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(
    err.message().contains("cannot appear inside a numeric expression"),
    true,
  )
}

///|
test "error: numeric effect in init" {
  let err = try {
    ignore(
      parse_problem(
        "(define (problem p) (:domain d) (:init (increase (f) 1)) (:goal (ready)))",
      ),
    )
    abort("expected a parse error")
  } catch {
    err => err
  }
  @test.assert_eq(
    err.message().contains("numeric effects are not allowed"),
    true,
  )
}
