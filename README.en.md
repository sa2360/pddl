# moonpddl

[![CI](https://github.com/sa2360/pddl/actions/workflows/ci.yml/badge.svg)](https://github.com/sa2360/pddl/actions/workflows/ci.yml)

**A PDDL planning engine and independent plan validator written in MoonBit,
with full PDDL 2.1 Level 1 support.**

moonpddl parses standard PDDL domain and problem files, grounds them into an
explicit state-space task, and searches forward with delete-relaxation
heuristics. Its validator replays arbitrary plans independently, checking
applicability, goal satisfaction, and action costs step by step. Parsing,
grounding, heuristics, search, and validation are implemented entirely in
MoonBit; the core library has no external solver dependency.

[中文文档](README.md)

```text
$ moon run --target native cmd/moonpddl -- solve \
    examples/blocksworld/domain.pddl examples/blocksworld/problem.pddl \
    -s astar -H hmax
; moonpddl: solved
; cost = 4
; expanded = 6, generated = 11
; heuristic = hmax, search = astar
(pick-up b)
(stack b c)
(pick-up a)
(stack a b)
```

## Why PDDL

PDDL is the standard modelling language of classical AI planning, used by the
International Planning Competition and a large body of planning research. A
useful PDDL toolchain has to combine typed first-order formula compilation,
conditional-effect and quantified grounding semantics, full numeric fluent
evaluation in preconditions, goals, and effects, admissible delete-relaxation
heuristics, forward state-space search, and a validator that reports precise
diagnostics. Before this project was published (as of 2026-10-21), mooncakes.io
had no PDDL planner or plan validator; moonpddl brings this complete
application domain to the MoonBit ecosystem rather than wrapping an existing
MoonBit package.

## Conformance endpoint: full PDDL 2.1 Level 1

moonpddl targets a precise, checkable standard level rather than a vague
"common subset": **the complete syntax and semantics of PDDL 2.1 Level 1
(classical planning with numeric fluents), plus the PDDL 3.1 `:action-costs`
requirement flag**. Level 2 and above (durative actions, continuous effects,
the PDDL+ temporal model) are out of scope and are rejected with explicit
errors instead of being ignored.

Item-by-item coverage of the PDDL 2.1 Level 1 grammar:

| Category | Support |
| --- | --- |
| Requirements | `:strips`, `:typing`, `:negative-preconditions`, `:disjunctive-preconditions`, `:equality`, `:existential-preconditions`, `:universal-preconditions`, `:quantified-preconditions`, `:conditional-effects`, `:fluents`, `:adl` (domain or problem), plus `:action-costs` |
| Types | Multiple-inheritance hierarchy (`:types t - (either a b)`); objects, constants, parameters, and quantified variables all accept `(either t1 t2 ...)` with union semantics |
| Propositional formulas | `and`, `or`, `not`, `imply`, `exists`, `forall`, object equality `=`, arbitrarily nested |
| Numeric expressions | Integer and real literals, unary minus, `+`/`*` (n-ary), `-` (binary/unary), `/`, function terms of any arity, arbitrarily nested |
| Numeric comparisons | `<`, `<=`, `=`, `>`, `>=` in preconditions, effect conditions, and goals |
| Function declarations | `(:functions ...)` with any 0-ary/n-ary functions, typed parameters, `number` return type |
| Numeric effects | `increase`, `decrease`, `assign`, `scale-up`, `scale-down` on any function with a full expression on the right-hand side, combinable with `when`/`forall` (see semantics for `total-cost`) |
| Initial state | Propositional facts plus `(= (f args) value)` for any function; negative and fractional values allowed |
| Optimization metric | `:metric minimize/maximize` over a full numeric expression, including the bare `total-cost` spelling |
| Action costs | `total-cost` accumulation; cost expressions accept the spec-allowed **static function inputs**, e.g. `(increase (total-cost) (* (fuel-price) (distance ?a ?b)))` |
| Plan text | One action per line, optional parentheses, case-insensitive, `;` comments, `; cost = N` with decimals |

Unsupported constructs are rejected explicitly: durative actions,
`:duration-inequalities`, continuous effects, derived predicates, `object`
fluents, preferences and constraints, `:extends`, and unknown requirement
flags — with line/column positions or concrete reasons. Every row of the table
is pinned by tests (`conformance_wbtest.mbt` and the conformance cases in the
other test files).

## Features

- **Front end**: lexer, S-expression reader, and PDDL parser with line/column
  positions. Invalid or unsupported constructs raise a structured `PddlError`.
- **Typed grounding**: type hierarchy (including either-types), domain
  constants plus problem objects, argument type checks, quantifier expansion,
  DNF compilation, conditional effect factoring, numeric expression
  compilation, and explicit limits on DNF branches and ground actions.
- **Reachability pruning**: after grounding, a delete-relaxation forward
  reachability pass drops ground actions whose preconditions can never become
  true (a sound over-approximation).
- **Five heuristics**: `blind`, `goal-count`, `hmax`, `hadd`, and `hff`. `hmax`
  works on the delete relaxation and is admissible for non-negative costs;
  numeric constraints are dropped in the relaxation, so admissibility holds
  for the real task as well.
- **Three searches**: GBFS, A\*, and weighted A\* (WA\*) with a binary heap,
  best-g deduplication, node reopening in A\*, configurable budgets, and
  fluent values participating in duplicate detection.
- **Independent validator**: re-parses plan text, re-executes every step, and
  reports unknown actions, bad arguments, inapplicable steps (including
  unsatisfied numeric preconditions), unreached goals, and `; cost = N`
  annotation mismatches (which invalidate the plan).
- **CLI and JSON**: `solve`, `validate`, `check`, and `ground` subcommands with
  stable exit codes and one-line JSON output.
- **Reproducible project**: five runnable examples, 91 unit/integration tests,
  wasm and native targets, and optional benchmarks.

## Quick start

Requires the MoonBit toolchain (`moon`). The library is published on
[mooncakes](https://mooncakes.io/docs/sa2360/pddl):

```bash
moon add sa2360/pddl
```

To work on this repository, run:

```bash
moon check
moon test
moon test --target native
moon build --target native cmd/moonpddl
```

The output location of the native executable varies between toolchain
versions, so the easiest way to run the CLI is through `moon`:

```bash
moon run --target native cmd/moonpddl -- version
moon run --target native cmd/moonpddl -- check \
  examples/blocksworld/domain.pddl examples/blocksworld/problem.pddl
```

## CLI

```text
moonpddl solve <domain.pddl> <problem.pddl> [options]
moonpddl validate <domain.pddl> <problem.pddl> <plan.txt> [--json]
moonpddl check <domain.pddl> <problem.pddl> [--json]
moonpddl ground <domain.pddl> <problem.pddl> [--json]
moonpddl version
```

| Option | Meaning |
| --- | --- |
| `-s, --search <gbfs\|astar\|wastar>` | Search strategy (default `gbfs`) |
| `-H, --heuristic <name>` | `blind`, `goal-count`, `hmax`, `hadd`, `hff` (default `hff`) |
| `--weight <n>` | WA\* weight, default 5 (only with `--search wastar`) |
| `--max-expanded <n>` | Expanded-state limit, default 1,000,000 |
| `--json` | Emit one-line JSON |
| `--out <path>` | Write the plan, prefixed by `; cost = N` |
| `-q, --quiet` | Suppress solver statistics |
| `-h, --help` | Show help |

Exit codes: `0` success; `1` no plan or invalid plan; `2` usage, parse, model, or
I/O error.

```bash
# Solve a numeric domain optimally
moon run --target native cmd/moonpddl -- solve \
  examples/delivery-numeric/domain.pddl examples/delivery-numeric/problem.pddl \
  -s astar -H hmax

# Validate
moon run --target native cmd/moonpddl -- validate \
  examples/logistics/domain.pddl examples/logistics/problem.pddl \
  examples/logistics/plan.pddl
# plan valid: 9 step(s), cost 9

# Inspect the grounded model
moon run --target native cmd/moonpddl -- ground \
  examples/blocksworld/domain.pddl examples/blocksworld/problem.pddl
```

JSON solve output:

```json
{"status":"solved","cost":34,"steps":3,"expanded":6,"generated":12,
 "heuristic":"hmax","search":"astar",
 "plan":["(drive t1 a b)","(refuel t1 b)","(drive t1 b c)"]}
```

JSON validation output:

```json
{"valid":true,"steps":9,"executed":9,"cost":9,"declared_cost":9,"issues":[]}
```

## Library API

The root package `sa2360/pddl` exposes the whole pipeline:

```moonbit
let domain = @pddl.parse_domain(domain_source)
let problem_ast = @pddl.parse_problem(problem_source)
let problem = @pddl.ground(domain, problem_ast)
let result = @pddl.solve(problem, @pddl.HFF, @pddl.AStar)
let plan_text = result.render_plan(problem)
let report = @pddl.validate_plan(problem, plan_text)
inspect(report.valid, content="true")
```

Key entry points: `parse_domain`, `parse_problem`, `ground`, `solve`,
`heuristic_value`, `validate`, `validate_plan`,
`ValidationReport::to_json`, plus the numeric helpers `eval_num_value`,
`num_compare`, and `format_number`. `SearchResult.plan` stores indices into
`GroundProblem.actions`; `render_plan` converts them to plan text. Reported
cost includes the initial `total-cost` from `:init`.

## Semantics

1. Preconditions are compiled to DNF; any satisfied disjunct makes the action
   applicable. Numeric comparisons are constraints inside a disjunct and are
   evaluated on the pre-action state.
2. Conditional effect conditions (including numeric comparisons) are evaluated
   in the pre-action state; deletes and adds are then collected, deletes apply
   first, and **adds win**.
3. Numeric effect right-hand sides are evaluated in the pre-action state. Per
   fluent: `increase`/`decrease` accumulate additively, then `scale-up`/
   `scale-down` apply in encounter order (division by zero is a no-op for that
   effect), and `assign` overrides everything with the last assignment
   winning. Division by zero inside a condition evaluates to 0.
4. Cost mode is enabled by `:action-costs`, a `total-cost` effect or initial
   assignment, or a `:metric` mentioning `total-cost`; actions then start at
   cost 0 and accumulate `increase (total-cost)` effects. Otherwise actions
   have unit cost 1. `total-cost` may only be increased, unconditionally.
   Cost expressions may only read **static functions** (assigned in `:init`
   and never modified) — matching Fast Downward. Costs are `Double`, exact
   for integer values up to 2^53; per-action and initial costs are capped at
   10^12 and sums saturate at 10^15.
5. Goals are also compiled to DNF over the grounded atom and fluent tables.
   `total-cost` never becomes a state fluent (it is the path cost `g`), so
   conditions mentioning it are rejected.
6. The metric direction and expression are recorded; search always minimizes
   cost (`total-cost`). `maximize` tasks still yield valid plans, but the
   maximization objective is not optimized.
7. Numeric precision: fluents and costs are IEEE 754 doubles; comparisons use
   a 1e-9 tolerance, and values close to integers are canonicalized in state
   keys and output. Integers and simple fractions (0.5, 3.25, ...) stay exact.

## Architecture

```text
PDDL text
   │  lexer.mbt + sexp.mbt
   ▼
S-expressions (with positions)
   │  parser.mbt → ast.mbt
   ▼
Domain / Problem
   │  ground.mbt (types, objects, quantifiers, DNF, numeric compilation, costs, pruning)
   ▼
GroundProblem (atom table + fluent table + bitset/array State + ground actions)
   ├── heuristics.mbt (delete relaxation: hmax / hadd / hff)
   │        └── search.mbt (GBFS / A* / WA*) → SearchResult → plan text
   └── validate.mbt (independent replay) → ValidationReport (text / JSON)
```

| File | Responsibility |
| --- | --- |
| `lexer.mbt`, `sexp.mbt` | Tokenization and S-expression reading with positions |
| `parser.mbt`, `ast.mbt` | PDDL domain/problem parsing and AST (including numeric expressions) |
| `error.mbt` | `PddlError`, error categories, position formatting |
| `ground.mbt` | Type hierarchy, grounding, DNF, numeric state and effects, static costs, reachability pruning |
| `heuristics.mbt` | Delete-relaxed task, `hmax`, `hadd`, `hff`, goal count |
| `search.mbt` | Open list, GBFS/A\*/WA\*, budgets, plan reconstruction |
| `validate.mbt` | Plan parsing, independent execution, diagnostics, JSON |
| `cmd/moonpddl/` | Native CLI |

`hmax` computes minimum achievement costs on the delete relaxation and takes the
goal maximum; it is admissible for non-negative costs, so A\* returns optimal
plans. `hadd` sums goal costs and is usually more informative but not
admissible. `hff` extracts a relaxed plan and sums its action costs, which works
well with GBFS and WA\*.

## Examples

| Domain | Size | Demonstrates | Plan cost |
| --- | --- | --- | --- |
| [blocksworld](examples/blocksworld) | 3 blocks | STRIPS, typing, optimal search | 4 |
| [gripper](examples/gripper) | 2 balls, 2 grippers | Multiple object types and movement | 5 |
| [logistics](examples/logistics) | 2 cities, truck + airplane | Multiple vehicles, 9-step plan | 9 |
| [matchcellar](examples/matchcellar) | 2 matches, 2 fuses | Action costs and `:metric` | 4 |
| [delivery-numeric](examples/delivery-numeric) | 3 places, 1 truck | Numeric fluents, static function cost inputs, numeric preconditions and effects | 34 |

Each directory contains `domain.pddl`, `problem.pddl`, and a hand-checked
`plan.pddl`:

```bash
moon run --target native cmd/moonpddl -- validate \
  examples/delivery-numeric/domain.pddl examples/delivery-numeric/problem.pddl \
  examples/delivery-numeric/plan.pddl
# plan valid: 3 step(s), cost 34
```

## Testing and benchmarks

```bash
moon test                                      # 91 tests on wasm
moon test --target native                      # same suite on native
moon test --include-skipped -f "benchmarks:*"  # optional benchmarks
```

The suite includes a dedicated conformance battery (`conformance_wbtest.mbt`)
that pins the Level 1 grammar and semantics row by row.

Benchmarks use `moonbitlang/core/bench` on the blocksworld fixture. One sample
from a local wasm debug build (10 runs, microseconds, indicative only):

| Stage | Median |
| --- | --- |
| Parse domain + problem | ≈ 108 µs |
| Ground (24 actions, incl. pruning) | ≈ 246 µs |
| GBFS + `hff` solve | ≈ 262 µs |
| Validate a 4-step plan | ≈ 33 µs |

CI runs `moon fmt --check`, `moon check --deny-warn`, wasm and native tests, a
native CLI build, validation of every example plan, and optimal solves of
blocksworld and delivery-numeric.

## Limitations

- Grounding is full; action counts grow combinatorially with objects. The
  current caps are 200,000 ground actions, 8,192 DNF branches, and a nesting
  depth of 256 for formulas, effects, and numeric expressions (deeper input
  is rejected with an error, not a crash). Grounding is followed by a
  delete-relaxation reachability prune, but there is no relevance-analysis
  based pruning at grounding time.
- Search is forward best-first; there is no semantic pruning, landmark
  heuristic, SAS+ compilation, or symbolic search yet.
- PDDL 2.1 **Level 2 and above** (durative actions, continuous effects, the
  PDDL+ temporal model) and the PDDL 2.2/3.x extensions (derived predicates,
  timed initial literals, preferences, constraints) are outside the
  conformance endpoint and are rejected explicitly.
- Action cost expressions may only read static functions (matching Fast
  Downward); state-dependent costs are rejected with a clear error. A
  `maximize` metric is recorded but not optimized.
- GBFS orders by `h` and is not optimal; use admissible `hmax + A*` when
  optimality matters.
- The validator replays plans independently but shares the grounding semantics
  with the planner; it does not re-derive domain semantics on its own.

Planned work: relevance-based grounding, landmark heuristics, plan
post-processing, a browser/wasm demo, and PDDL 2.2 derived predicates.

## AI assistance disclosure

AI coding assistants (Qoder, ZCode) helped implement code, design tests, write
documentation, and debug the CLI. All committed code was checked locally with
`moon check`, the 91-test suite, wasm/native runs, and validation of all five
example plans. The author is responsible for the final design and correctness.

## License

[MIT](LICENSE)

## References

- D. McDermott et al., *PDDL — The Planning Domain Definition Language*.
- M. Fox and D. Long, *PDDL2.1: An Extension to PDDL for Expressing Planning
  Domains with Numeric Fluents*.
- J. Hoffmann and B. Nebel, *The FF Planning System: Fast Plan Generation
  Through Heuristic Search*, JAIR 2001.
- M. Helmert, *The Fast Downward Planning System*, JAIR 2006.
