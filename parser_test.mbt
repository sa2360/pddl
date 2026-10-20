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
  @test.assert_eq(domain.types[0].parent, "object")
  @test.assert_eq(domain.predicates.length(), 5)
  @test.assert_eq(domain.actions.length(), 4)
  let pick_up = domain.actions[0]
  @test.assert_eq(pick_up.name, "pick-up")
  @test.assert_eq(pick_up.params.length(), 1)
  @test.assert_eq(pick_up.params[0].name, "x")
  @test.assert_eq(pick_up.params[0].type_name, "block")
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
  @test.assert_eq(domain.types[0].parent, "vehicle")
  @test.assert_eq(domain.types[1].parent, "vehicle")
  @test.assert_eq(domain.types[2].parent, "object")
  @test.assert_eq(domain.constants.length(), 3)
  @test.assert_eq(domain.constants[1].name, "t1")
  @test.assert_eq(domain.constants[1].type_name, "truck")
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
        IncreaseEffect(fluent, amount) => {
          @test.assert_eq(fluent, "total-cost")
          @test.assert_eq(amount, 2)
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
      @test.assert_eq(vars[0].type_name, "block")
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
    InitCost(amount) => @test.assert_eq(amount, 0)
    _ => abort("expected an init cost")
  }
  @test.assert_eq(problem.metric is Some(MinimizeTotalCost), true)
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
