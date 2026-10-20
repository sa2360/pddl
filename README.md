# moonpddl

[![CI](https://github.com/sa2360/pddl/actions/workflows/ci.yml/badge.svg)](https://github.com/sa2360/pddl/actions/workflows/ci.yml)

**用 MoonBit 编写的 PDDL 规划引擎与独立计划验证器。**

moonpddl 读取标准 PDDL 领域与问题文件，将其编译为显式接地的状态空间任务，
再用删除松弛启发式驱动前向搜索；配套验证器可以独立重放任意计划，逐步检查
动作可应用性、目标满足情况与动作代价。解析、接地、启发式、搜索与验证全部由
MoonBit 实现，核心库不依赖任何外部求解器。

[English documentation](README.en.md)

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

## 为什么是 PDDL

PDDL（Planning Domain Definition Language）是经典人工智能规划领域的标准建模
语言，被 IPC（International Planning Competition）与大量规划研究使用。与解析
器、序列化格式等通用基础库不同，本项目需要同时实现：

- 带类型层次与量词的一阶逻辑公式编译；
- 条件效果、负前提、析取目标下的接地语义；
- 可采纳的删除松弛启发式与前向状态空间搜索；
- 与求解器解耦、可定位到源码行的计划验证。

截至 2026-10-21，mooncakes.io 上未检索到 PDDL 规划器或计划验证器包；
本项目不是对现有 MoonBit 库的重复封装，而是把经典规划这一完整应用领域带入
MoonBit 生态。

## 功能特性

- **完整前端**：词法分析、S 表达式解析、带行列位置的 PDDL 解析；语法错误与
  不支持构造均返回结构化 `PddlError`，不使用全局状态或静默降级。
- **类型化接地**：支持类型继承层次、域常量与问题对象合并、参数类型检查、
  量词展开、公式 DNF 编译、条件效果因式分解，并限制 DNF 与接地动作规模。
- **五种启发式**：`blind`、`goal-count`、`hmax`、`hadd`、`hff`。其中 `hmax`
  基于删除松弛，在非负动作代价下可采纳。
- **三种搜索策略**：GBFS、A\*、加权 A\*（WA\*）。二叉堆开放表、`best-g`
  去重、A\* 更优路径重开、可配置扩展/生成上限。
- **独立验证器**：不依赖搜索轨迹，重新解析计划文本并逐步执行；报告未知动作、
  错误参数、不可应用步骤、未达成目标，以及 `; cost = N` 标注不一致。
- **CLI 与 JSON**：`solve` / `validate` / `check` / `ground` 四个子命令，
  稳定退出码与机器可读输出，适合脚本与 CI 集成。
- **可复现工程**：四个可运行示例、41 个单元/集成测试、跨 wasm 与 native
  目标验证、可选的性能基准。

## 快速开始

要求 MoonBit 工具链（`moon`）已安装。

```bash
# 静态检查与测试（默认 wasm 目标）
moon check
moon test

# 同时验证 native 后端
moon test --target native

# 构建原生 CLI
moon build --target native cmd/moonpddl
```

构建产物的默认位置为
`_build/native/debug/build/cmd/moonpddl/moonpddl.exe`（Windows）或
`_build/native/debug/build/cmd/moonpddl/moonpddl`（Unix）。也可以直接用
`moon run`：

```bash
moon run cmd/moonpddl --target native -- version
moon run cmd/moonpddl --target native -- check \
  examples/blocksworld/domain.pddl examples/blocksworld/problem.pddl
```

## 命令行用法

```text
moonpddl solve <domain.pddl> <problem.pddl> [options]
moonpddl validate <domain.pddl> <problem.pddl> <plan.txt> [--json]
moonpddl check <domain.pddl> <problem.pddl> [--json]
moonpddl ground <domain.pddl> <problem.pddl> [--json]
moonpddl version
```

| 选项 | 说明 |
| --- | --- |
| `-s, --search <gbfs\|astar\|wastar>` | 搜索策略，默认 `gbfs` |
| `-H, --heuristic <name>` | `blind`、`goal-count`、`hmax`、`hadd`、`hff`，默认 `hff` |
| `--weight <n>` | WA\* 权重，默认 5；仅能与 `--search wastar` 共用 |
| `--max-expanded <n>` | 扩展状态上限，默认 1,000,000 |
| `--json` | 输出单行 JSON |
| `--out <path>` | 将计划写入文件，首行为 `; cost = N` |
| `-q, --quiet` | 不输出求解统计 |
| `-h, --help` | 显示帮助 |

退出码：`0` 成功；`1` 未找到计划或计划无效；`2` 用法错误、解析错误、模型错误
或文件读取失败。

### 求解

```bash
moon run cmd/moonpddl --target native -- solve \
  examples/logistics/domain.pddl examples/logistics/problem.pddl \
  -s wastar --weight 3 -H hmax
```

```text
; moonpddl: solved
; cost = 7
; expanded = 22, generated = 51
; heuristic = hmax, search = wastar(3)
(fly-airplane pl1 b a)
(load-airplane p1 pl1 a)
...
```

机器可读输出：

```json
{"status":"solved","cost":4,"steps":4,"expanded":6,"generated":11,
 "heuristic":"hmax","search":"astar",
 "plan":["(pick-up b)","(stack b c)","(pick-up a)","(stack a b)"]}
```

`status` 为 `solved`、`exhausted` 或 `limit`。`plan` 中的每一步都是可直接用于
`validate` 的 `(action args)` 文本。

### 验证

```bash
moon run cmd/moonpddl --target native -- validate \
  examples/logistics/domain.pddl examples/logistics/problem.pddl \
  examples/logistics/plan.pddl
# plan valid: 9 step(s), cost 9
```

```json
{"valid":true,"steps":9,"executed":9,"cost":9,"declared_cost":9,"issues":[]}
```

验证失败时，`issues` 会给出类别、计划行号与步骤号：

```text
step 1 ((pick ball1 rooma left)) uses unknown action 'pick'
  line 2: [unknown-action] step 1 ((pick ball1 rooma left)) uses unknown action 'pick'
```

### 查看模型与接地结果

```bash
moon run cmd/moonpddl --target native -- check \
  examples/blocksworld/domain.pddl examples/blocksworld/problem.pddl
```

```text
model ok
  domain: blocksworld
  problem: blocks-3
  objects: 3
  atoms: 19
  actions: 24
  goal disjuncts: 1
  initial cost: 0
  cost mode: unit
```

`ground` 在此基础上还会列出每个接地动作及其代价。

## 库 API

根包 `sa2360/pddl` 暴露解析、接地、搜索与验证接口。最小流程：

```moonbit
let domain = @pddl.parse_domain(domain_source)
let problem_ast = @pddl.parse_problem(problem_source)
let problem = @pddl.ground(domain, problem_ast)
let result = @pddl.solve(problem, @pddl.HFF, @pddl.AStar)
let plan_text = result.render_plan(problem)
let report = @pddl.validate_plan(problem, plan_text)
inspect(report.valid, content="true")
```

主要入口：

| API | 说明 |
| --- | --- |
| `parse_domain` / `parse_problem` | 解析 PDDL，失败时抛出带位置的 `PddlError` |
| `ground` | 将领域与问题编译为 `GroundProblem` |
| `solve` | 按给定启发式与策略搜索，返回 `SearchResult` |
| `heuristic_value` | 计算某个状态在指定启发式下的估计值 |
| `validate` | 一次性完成解析 + 接地 + 验证 |
| `validate_plan` | 在已有 `GroundProblem` 上验证计划 |
| `ValidationReport::to_json` | 将验证结果序列化为 JSON |
| `State` / `apply_action` | 位集状态与动作前向执行，可用于自定义搜索 |

`SearchResult.plan` 保存的是 `GroundProblem.actions` 的下标；`render_plan` 负责
转换为标准计划文本。计划代价包含问题 `:init` 中的初始 `total-cost`。

## 支持的 PDDL 子集

| 类别 | 支持内容 |
| --- | --- |
| 需求标记 | `:strips`、`:typing`、`:negative-preconditions`、`:disjunctive-preconditions`、`:equality`、`:existential-preconditions`、`:universal-preconditions`、`:quantified-preconditions`、`:conditional-effects`、`:action-costs`、`:adl` |
| 类型 | 单继承类型层次；对象类型按父类型兼容 |
| 公式 | `and`、`or`、`not`、`imply`、`exists`、`forall`、`=`，可任意嵌套 |
| 效果 | `and`、`not`、`forall`、`when`、`(increase (total-cost) N)` |
| 代价 | 仅 `(total-cost)`；非负整数；`:metric minimize (total-cost)` |
| 计划文本 | 每行一个动作，括号可省略，大小写不敏感，`;` 后为注释 |

明确拒绝而不静默忽略的构造包括：durative actions、除 `total-cost` 外的数值
fluent、`decrease`/`assign`/`scale-up`/`scale-down`、派生谓词、偏好与约束、
`:extends`、未知需求标记等。错误信息包含行列位置或具体原因。

### 语义约定

1. **前提条件**在接地阶段编译为 DNF；状态满足任一析取分支即可应用动作。
2. **条件效果**的条件在动作执行前状态上求值；随后统一收集删除与添加，先删除
   后添加，**添加优先**。
3. **代价模式**：出现 `:action-costs`、`total-cost` 声明或 `:metric` 时进入
   代价模式，动作基础代价为 0，由 `increase` 累加；否则为经典单位代价，每个
   动作代价为 1。条件式代价（`when` 内的 `increase`）会被拒绝。
4. **目标**同样编译为 DNF；初始状态与目标都只依赖接地原子表。

## 架构

```text
PDDL 文本
   │  lexer.mbt + sexp.mbt
   ▼
S 表达式（带行列位置）
   │  parser.mbt → ast.mbt
   ▼
Domain / Problem
   │  ground.mbt（类型、对象、量词、DNF、条件效果、代价）
   ▼
GroundProblem（原子表 + 位集 State + 接地动作）
   ├── heuristics.mbt（删除松弛：hmax / hadd / hff）
   │        └── search.mbt（GBFS / A* / WA*）→ SearchResult → 计划文本
   └── validate.mbt（独立重放）→ ValidationReport（文本 / JSON）
```

| 文件 | 职责 |
| --- | --- |
| `lexer.mbt`、`sexp.mbt` | 词法与 S 表达式读取，记录源码位置 |
| `parser.mbt`、`ast.mbt` | PDDL 领域/问题解析与 AST |
| `error.mbt` | `PddlError`、错误分类与位置格式化 |
| `ground.mbt` | 类型层次、接地、DNF 编译、状态与动作执行 |
| `heuristics.mbt` | 删除松弛任务、`hmax`、`hadd`、`hff`、目标计数 |
| `search.mbt` | 开放表、GBFS/A\*/WA\*、节点预算、计划重建 |
| `validate.mbt` | 计划文本解析、独立执行、诊断与 JSON 报告 |
| `cmd/moonpddl/` | 原生 CLI |

### 启发式与可采纳性

- `hmax` 在删除松弛上计算每个原子的最小达成代价并取目标最大值；在非负动作
  代价下可采纳。配合 `AStar` 得到最优计划。
- `hadd` 将目标代价求和，通常更有信息量但不可采纳。
- `hff` 在松弛任务上提取一条松弛计划并累加其代价，适合 GBFS/WA\*。
- `goal-count` 统计未满足目标字面量数；`blind` 恒为 0。

## 示例

| 领域 | 规模 | 展示能力 | 计划代价 |
| --- | --- | --- | --- |
| [blocksworld](examples/blocksworld) | 3 个积木 | STRIPS、类型、最优搜索 | 4 |
| [gripper](examples/gripper) | 2 个球、2 个夹爪 | 多类型对象与移动 | 5 |
| [logistics](examples/logistics) | 2 城市、卡车 + 飞机 | 多交通工具、9 步计划 | 9 |
| [matchcellar](examples/matchcellar) | 2 根火柴、2 个保险丝 | 动作代价与 `:metric` | 4 |

每个目录都包含 `domain.pddl`、`problem.pddl` 与手工核对的 `plan.pddl`：

```bash
moon run cmd/moonpddl --target native -- validate \
  examples/matchcellar/domain.pddl examples/matchcellar/problem.pddl \
  examples/matchcellar/plan.pddl
# plan valid: 4 step(s), cost 4
```

## 测试与基准

```bash
moon test                     # 41 个测试，wasm
moon test --target native     # 同一套测试，native
moon test --include-skipped -f "benchmarks:*"   # 可选性能基准
```

基准使用 `moonbitlang/core/bench`，在 blocksworld 夹具上测量解析、接地、搜索与
验证。以下是本机 wasm 调试构建的一次采样（10 次运行，单位为微秒，仅作量级
参考）：

| 阶段 | 中位耗时 |
| --- | --- |
| 解析领域 + 问题 | ≈ 116 µs |
| 接地（24 个动作） | ≈ 188 µs |
| GBFS + `hff` 求解 | ≈ 248 µs |
| 验证 4 步计划 | ≈ 22 µs |

CI（[.github/workflows/ci.yml](.github/workflows/ci.yml)）在 Ubuntu 上执行
`moon fmt --check`、`moon check --deny-warn`、wasm/native 双后端测试、原生 CLI
构建，并验证全部示例计划。

## 限制与路线图

- 采用**完全接地**，动作数随对象数量组合增长；当前上限为 200,000 个接地动作、
  8,192 个 DNF 分支。尚无基于可达性的静态剪枝。
- 搜索为前向最佳优先；尚无语义剪枝、landmark、SAS+ 或符号搜索。
- 数值支持限定于 `total-cost`，不支持 durative actions、连续效果或 PDDL+
  时态模型。
- 计划验证基于同一套接地语义；它会独立重放计划，但不会重新推导领域语义。

后续计划包括：接地相关性剪枝、landmark 启发式、计划后处理（去除冗余步骤）、
浏览器内 wasm 演示，以及更完整的 PDDL 3 约束支持。

## 开发说明与 AI 使用披露

本项目在开发过程中使用了 AI 编程助手（Qoder）协助代码实现、测试用例设计、
文档撰写与命令行调试。所有提交代码均经过本地 `moon check`、41 个测试、
wasm/native 双后端运行以及四个示例计划验证；作者对最终代码、设计与正确性负责。

欢迎提交 issue 与 PR。

## 许可证

[MIT](LICENSE)

## 参考

- D. McDermott et al., *PDDL — The Planning Domain Definition Language*.
- J. Hoffmann and B. Nebel, *The FF Planning System: Fast Plan Generation
  Through Heuristic Search*, JAIR 2001.
- M. Helmert, *The Fast Downward Planning System*, JAIR 2006.
