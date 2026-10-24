// Copyright 2026 moonpddl contributors
//
// SPDX-License-Identifier: MIT

///|
#skip("benchmark")
test "benchmarks: parse, ground, solve, validate" {
  let bencher = @bench.Bench()
  bencher.bench(name="parse_domain+problem", count=10, () => {
    ignore(try! parse_domain(blocksworld_domain))
    ignore(try! parse_problem(blocksworld_problem))
  })
  let domain = try! parse_domain(blocksworld_domain)
  let problem = try! parse_problem(blocksworld_problem)
  bencher.bench(name="ground_blocksworld", count=10, () => {
    ignore(try! ground(domain, problem))
  })
  let grounded = try! ground(domain, problem)
  bencher.bench(name="solve_gbfs_hff", count=10, () => {
    ignore(solve(grounded, HFF, GBFS))
  })
  let result = solve(grounded, HFF, GBFS)
  let source = "; cost = \{format_number(result.cost)}\n" +
    result.render_plan(grounded)
  bencher.bench(name="validate_plan", count=10, () => {
    ignore(validate_plan(grounded, source))
  })
  let report = bencher.dump_summaries()
  println(report)
  inspect(report.contains("solve_gbfs_hff"), content="true")
}
