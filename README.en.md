# moonpddl

**A PDDL planning engine and independent plan validator written in MoonBit.**

moonpddl parses standard PDDL domain and problem files, grounds them into an
explicit state-space task, and searches forward with delete-relaxation
heuristics. Its validator replays arbitrary plans independently, checking
applicability, goal satisfaction, and action costs step by step. Parsing,
grounding, heuristics, search, and validation are implemented entirely in
MoonBit; the core library has no external solver dependency.

[中文文档](README.md)

```text
$ moon run cmd/moonpddl --target native -- solve \
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
conditional-effect and quantified grounding semantics, admissible
delete-relaxation heuristics, forward state-space search, and a validator that
reports precise diagnostics. As of 2026-10-21 there is no PDDL planner or plan
validator on mooncakes.io; moonpddl brings this complete application domain to
the MoonBit ecosystem rather than wrapping an existing MoonBit package.

## Features

- **Front end**: lexer, S-expression reader, and PDDL parser with line/column
  positions. Invalid or unsupported constructs raise a structured `PddlError`.
- **Typed grounding**: type hierarchy, domain constants plus problem objects,
  argument type checks, quantifier expansion, DNF compilation, conditional
  effect factoring, and explicit limits on DNF branches and ground actions.
- **Five heuristics**: `blind`, `goal-count`, `hmax`, `hadd`, and `hff`. `hmax`
  works on the delete relaxation and is admissible for non-negative costs.
- **Three searches**: GBFS, A\*, and weighted A\* (WA\*) with a binary heap,
  best-g deduplication, node reopening in A\*, and configurable budgets.
- **Independent validator**: re-parses plan text, re-executes every step, and
  reports unknown actions, bad arguments, inapplicable steps, unreached goals,
  and `; cost = N` annotation mismatches.
- **CLI and JSON**: `solve`, `validate`, `check`, and `ground` subcommands with
  stable exit codes and one-line JSON output.
- **Reproducible project**: four runnable examples, 41 unit/integration tests,
  wasm and native targets, and optional benchmarks.

## Quick start

Requires the MoonBit toolchain (`moon`).

```bash
moon check
moon test
moon test --target native
moon build --target native cmd/moonpddl
```

The native executable is written to
`_build/native/debug/build/cmd/moonpddl/moonpddl.exe` on Windows and
`_build/native/debug/build/cmd/moonpddl/moonpddl` on Unix. You can also run it
through `moon`:

```bash
moon run cmd/moonpddl --target native -- version
moon run cmd/moonpddl --target native -- check \
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
# Solve
moon run cmd/moonpddl --target native -- solve \
  examples/logistics/domain.pddl examples/logistics/problem.pddl \
  -s wastar --weight 3 -H hmax

# Validate
moon run cmd/moonpddl --target native -- validate \
  examples/logistics/domain.pddl examples/logistics/problem.pddl \
  examples/logistics/plan.pddl
# plan valid: 9 step(s), cost 9

# Inspect the grounded model
moon run cmd/moonpddl --target native -- ground \
  examples/blocksworld/domain.pddl examples/blocksworld/problem.pddl
```

JSON solve output:

```json
{"status":"solved","cost":4,"steps":4,"expanded":6,"generated":11,
 "heuristic":"hmax","search":"astar",
 "plan":["(pick-up b)","(stack b c)","(pick-up a)","(stack a b)"]}
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
`heuristic_value`, `validate`, `validate_plan`, and
`ValidationReport::to_json`. `SearchResult.plan` stores indices into
`GroundProblem.actions`; `render_plan` converts them to plan text. Reported cost
includes the initial `total-cost` from `:init`.

## Supported PDDL subset

| Category | Support |
| --- | --- |
| Requirements | `:strips`, `:typing`, `:negative-preconditions`, `:disjunctive-preconditions`, `:equality`, `:existential-preconditions`, `:universal-preconditions`, `:quantified-preconditions`, `:conditional-effects`, `:action-costs`, `:adl` |
| Types | Single-inheritance hierarchy; arguments accept subtypes |
| Formulas | `and`, `or`, `not`, `imply`, `exists`, `forall`, `=`, arbitrarily nested |
| Effects | `and`, `not`, `forall`, `when`, `(increase (total-cost) N)` |
| Costs | `(total-cost)` only, non-negative integers, `:metric minimize (total-cost)` |
| Plan text | One action per line, optional parentheses, case-insensitive, `;` comments |

Unsupported constructs are rejected explicitly: durative actions, numeric
fluents other than `total-cost`, `decrease`/`assign`/`scale-up`/`scale-down`,
derived predicates, preferences and constraints, `:extends`, and unknown
requirement flags.

### Semantics

1. Preconditions are compiled to DNF; any satisfied disjunct makes the action
   applicable.
2. Conditional effect conditions are evaluated in the pre-action state, then
   deletes and adds are collected; deletes apply first and **adds win**.
3. Cost mode is enabled by `:action-costs`, a `total-cost` declaration, or a
   `:metric`; actions then start at cost 0 and accumulate `increase` effects.
   Otherwise actions have unit cost 1. Conditional costs are rejected.
4. Goals are also compiled to DNF and evaluated over the grounded atom table.

## Architecture

```text
PDDL text
   │  lexer.mbt + sexp.mbt
   ▼
S-expressions (with positions)
   │  parser.mbt → ast.mbt
   ▼
Domain / Problem
   │  ground.mbt (types, objects, quantifiers, DNF, conditional effects, costs)
   ▼
GroundProblem (atom table + bitset State + ground actions)
   ├── heuristics.mbt (delete relaxation: hmax / hadd / hff)
   │        └── search.mbt (GBFS / A* / WA*) → SearchResult → plan text
   └── validate.mbt (independent replay) → ValidationReport (text / JSON)
```

| File | Responsibility |
| --- | --- |
| `lexer.mbt`, `sexp.mbt` | Tokenization and S-expression reading with positions |
| `parser.mbt`, `ast.mbt` | PDDL domain/problem parsing and AST |
| `error.mbt` | `PddlError`, error categories, position formatting |
| `ground.mbt` | Type hierarchy, grounding, DNF, state and action execution |
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

Each directory contains `domain.pddl`, `problem.pddl`, and a hand-checked
`plan.pddl`:

```bash
moon run cmd/moonpddl --target native -- validate \
  examples/matchcellar/domain.pddl examples/matchcellar/problem.pddl \
  examples/matchcellar/plan.pddl
# plan valid: 4 step(s), cost 4
```

## Testing and benchmarks

```bash
moon test                                      # 41 tests on wasm
moon test --target native                      # same suite on native
moon test --include-skipped -f "benchmarks:*"  # optional benchmarks
```

Benchmarks use `moonbitlang/core/bench` on the blocksworld fixture. One sample
from a local wasm debug build (10 runs, microseconds, indicative only):

| Stage | Median |
| --- | --- |
| Parse domain + problem | ≈ 116 µs |
| Ground (24 actions) | ≈ 188 µs |
| GBFS + `hff` solve | ≈ 248 µs |
| Validate a 4-step plan | ≈ 22 µs |

CI runs `moon fmt --check`, `moon check --deny-warn`, wasm and native tests, a
native CLI build, and validates every example plan.

## Limitations

- Grounding is full; action counts grow combinatorially with objects. The
  current caps are 200,000 ground actions and 8,192 DNF branches. There is no
  reachability-based static pruning yet.
- Search is forward best-first; there is no semantic pruning, landmark
  heuristic, SAS+ compilation, or symbolic search yet.
- Numeric support is limited to `total-cost`; durative actions, continuous
  effects, and PDDL+ temporal models are not supported.
- The validator replays plans independently but shares the grounding semantics
  with the planner; it does not re-derive domain semantics on its own.

Planned work: relevance-based grounding, landmark heuristics, plan
post-processing, a browser/wasm demo, and broader PDDL 3 constraint support.

## AI assistance disclosure

An AI coding assistant (Qoder) helped implement code, design tests, write
documentation, and debug the CLI. All committed code was checked locally with
`moon check`, the 41-test suite, wasm/native runs, and validation of all four
example plans. The author is responsible for the final design and correctness.

## License

[MIT](LICENSE)

## References

- D. McDermott et al., *PDDL — The Planning Domain Definition Language*.
- J. Hoffmann and B. Nebel, *The FF Planning System: Fast Plan Generation
  Through Heuristic Search*, JAIR 2001.
- M. Helmert, *The Fast Downward Planning System*, JAIR 2006.
