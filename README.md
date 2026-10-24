# moonpddl

[![CI](https://github.com/sa2360/pddl/actions/workflows/ci.yml/badge.svg)](https://github.com/sa2360/pddl/actions/workflows/ci.yml)

**用 MoonBit 编写的 PDDL 规划引擎与独立计划验证器。完整支持 PDDL 2.1 Level 1。**

moonpddl 读取标准 PDDL 领域与问题文件，将其编译为显式接地的状态空间任务，
再用删除松弛启发式驱动前向搜索；配套验证器可以独立重放任意计划，逐步检查
动作可应用性、目标满足情况与动作代价。解析、接地、启发式、搜索与验证全部由
MoonBit 实现，核心库不依赖任何外部求解器。

[English documentation](README.en.md)

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

## 为什么是 PDDL

PDDL（Planning Domain Definition Language）是经典人工智能规划领域的标准建模
语言，被 IPC（International Planning Competition）与大量规划研究使用。与解析
器、序列化格式等通用基础库不同，本项目需要同时实现：

- 带类型层次与量词的一阶逻辑公式编译；
- 条件效果、负前提、析取目标下的接地语义；
- 数值 fluent（函数）在前提、目标与效果中的完整求值；
- 可采纳的删除松弛启发式与前向状态空间搜索；
- 与求解器解耦、可定位到源码行的计划验证。

本项目发布前（截至 2026-10-21），mooncakes.io 上未检索到 PDDL 规划器或计划
验证器包；本项目不是对现有 MoonBit 库的重复封装，而是把经典规划这一完整应用
领域带入 MoonBit 生态。

## 符合性终点：PDDL 2.1 Level 1 完整支持

moonpddl 的目标不是"某个常用子集"，而是一个明确、可检验的标准级别：
**PDDL 2.1 Level 1（经典 + 数值 fluent）的完整语法与语义，外加 PDDL 3.1 的
`:action-costs` 需求标记**。Level 2 及以上（durative actions、连续效果、
PDDL+ 时态模型）不在范围内，遇到时明确报错而不是静默忽略。

对照 PDDL 2.1 Level 1 语法逐项覆盖：

| 类别 | 支持内容 |
| --- | --- |
| 需求标记 | `:strips`、`:typing`、`:negative-preconditions`、`:disjunctive-preconditions`、`:equality`、`:existential-preconditions`、`:universal-preconditions`、`:quantified-preconditions`、`:conditional-effects`、`:fluents`、`:adl`（域与问题皆可声明），以及 `:action-costs` |
| 类型 | 多继承类型层次（`:types t - (either a b)`）；对象/常量/参数/量词变量均接受 `(either t1 t2 ...)` 并集语义 |
| 命题公式 | `and`、`or`、`not`、`imply`、`exists`、`forall`、对象相等 `=`，可任意嵌套 |
| 数值表达式 | 整数与实数字面量、一元负号、`+`/`*`（多元）、`-`（二元/一元）、`/`、任意参数的函数项，可任意嵌套 |
| 数值比较 | `<`、`<=`、`=`、`>`、`>=` 出现在前提、效果条件与目标中 |
| 函数声明 | `(:functions ...)` 任意 0 元/多元函数，参数带类型，返回类型 `number` |
| 数值效果 | `increase`、`decrease`、`assign`、`scale-up`、`scale-down` 作用于任意函数，右端为完整数值表达式，可与 `when`/`forall` 组合（total-cost 除外，见语义约定） |
| 初始状态 | 命题事实 + 任意函数的 `(= (f args) value)` 赋值，负数与小数均可 |
| 优化目标 | `:metric minimize/maximize` 作用于完整数值表达式（含 `total-cost` 的裸写法） |
| 动作代价 | `total-cost` 累计；代价表达式支持规范允许的**静态函数输入**，例如 `(increase (total-cost) (* (fuel-price) (distance ?a ?b)))` |
| 计划文本 | 每行一个动作，括号可省略，大小写不敏感，`;` 后为注释，`; cost = N` 支持小数 |

明确拒绝而不静默忽略的构造包括：durative actions、`:duration-inequalities`、
连续效果、派生谓词、`object` fluent（返回对象的函数）、偏好与约束、`:extends`、
未知需求标记等。错误信息包含行列位置或具体原因。每一行上表都有对应测试钉住
（见 `conformance_wbtest.mbt` 与各测试文件的符合性用例）。

## 功能特性

- **完整前端**：词法分析、S 表达式解析、带行列位置的 PDDL 解析；语法错误与
  不支持构造均返回结构化 `PddlError`，不使用全局状态或静默降级。
- **类型化接地**：类型层次（含 either 多继承）、域常量与问题对象合并、参数
  类型检查、量词展开、公式 DNF 编译、条件效果因式分解、数值表达式编译，
  并限制 DNF 与接地动作规模。
- **可达性剪枝**：接地后用删除松弛正向可达性剔除"前提永远无法满足"的接地
  动作（过近似，保证不丢失任何可用动作）。
- **五种启发式**：`blind`、`goal-count`、`hmax`、`hadd`、`hff`。其中 `hmax`
  基于删除松弛，在非负动作代价下可采纳；数值约束在松弛中被丢弃，因此
  可采纳性对真实任务依然成立。
- **三种搜索策略**：GBFS、A\*、加权 A\*（WA\*）。二叉堆开放表、`best-g`
  去重、A\* 更优路径重开、可配置扩展/生成上限；数值 fluent 值参与状态去重。
- **独立验证器**：不依赖搜索轨迹，重新解析计划文本并逐步执行；报告未知动作、
  错误参数、不可应用步骤（含未满足的数值前提）、未达成目标，以及
  `; cost = N` 标注不一致（判为无效）。
- **CLI 与 JSON**：`solve` / `validate` / `check` / `ground` 四个子命令，
  稳定退出码与机器可读输出，适合脚本与 CI 集成。
- **可复现工程**：五个可运行示例、91 个单元/集成测试、跨 wasm 与 native
  目标验证、可选的性能基准。

## 快速开始

要求 MoonBit 工具链（`moon`）已安装。库已发布到
[mooncakes](https://mooncakes.io/docs/sa2360/pddl)，可以直接引入：

```bash
moon add sa2360/pddl
```

若要在本仓库中开发、测试或构建 CLI：

```bash
# 静态检查与测试（默认 wasm 目标）
moon check
moon test

# 同时验证 native 后端
moon test --target native

# 构建原生 CLI
moon build --target native cmd/moonpddl
```

构建产物的位置随工具链版本变化，日常使用可以直接通过 `moon run` 调用，
无需关心具体路径：

```bash
moon run --target native cmd/moonpddl -- version
moon run --target native cmd/moonpddl -- check \
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
moon run --target native cmd/moonpddl -- solve \
  examples/delivery-numeric/domain.pddl examples/delivery-numeric/problem.pddl \
  -s astar -H hmax
```

```text
; moonpddl: solved
; cost = 34
; expanded = 6, generated = 12
; heuristic = hmax, search = astar
(drive t1 a b)
(refuel t1 b)
(drive t1 b c)
```

这个数值示例演示了 Level 1 的关键能力：`fuel`/`distance`/`fuel-price` 是
`:functions` 声明的数值 fluent，`distance` 与 `fuel-price` 是只在 `:init`
赋值的**静态函数**，动作代价表达式 `(* (fuel-price) (distance ?from ?to))`
直接读取它们；前提 `(>= (fuel ?t) (distance ?from ?to))` 是运行时数值比较；
效果里的 `(decrease (fuel ?t) ...)` 是数值效果。

机器可读输出：

```json
{"status":"solved","cost":34,"steps":3,"expanded":6,"generated":12,
 "heuristic":"hmax","search":"astar",
 "plan":["(drive t1 a b)","(refuel t1 b)","(drive t1 b c)"]}
```

`status` 为 `solved`、`exhausted` 或 `limit`。`plan` 中的每一步都是可直接用于
`validate` 的 `(action args)` 文本。

### 验证

```bash
moon run --target native cmd/moonpddl -- validate \
  examples/logistics/domain.pddl examples/logistics/problem.pddl \
  examples/logistics/plan.pddl
# plan valid: 9 step(s), cost 9
```

```json
{"valid":true,"steps":9,"executed":9,"cost":9,"declared_cost":9,"issues":[]}
```

验证失败时，`issues` 会给出类别、计划行号与步骤号，未满足的数值前提也会
原样渲染（例如 `(>= (fuel t1) 9)`）。

### 查看模型与接地结果

```bash
moon run --target native cmd/moonpddl -- check \
  examples/delivery-numeric/domain.pddl examples/delivery-numeric/problem.pddl
```

```text
model ok
  domain: delivery-numeric
  problem: delivery-1
  objects: 4
  atoms: 6
  fluents: 11
  actions: 12
  goal disjuncts: 1
  initial cost: 0
  cost mode: total-cost
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
| `State` / `apply_action` | 位集 + 数值 fluent 状态与动作前向执行，可用于自定义搜索 |
| `eval_num_value` / `num_compare` / `format_number` | 数值表达式求值、带容差比较与规范化输出 |

`SearchResult.plan` 保存的是 `GroundProblem.actions` 的下标；`render_plan` 负责
转换为标准计划文本。计划代价包含问题 `:init` 中的初始 `total-cost`。

## 语义约定

1. **前提条件**在接地阶段编译为 DNF；状态满足任一析取分支即可应用动作。
   数值比较是分支内的约束之一，在执行前的状态上求值。
2. **条件效果**的条件（含数值比较）在动作执行前状态上求值；随后统一收集
   删除与添加，先删除后添加，**添加优先**。
3. **数值效果**的右端表达式全部在执行前状态上求值。同一函数上：
   `increase`/`decrease` 先做代数和，随后按出现顺序应用 `scale-up`/
   `scale-down`（除以零时该项不生效）；`assign` 覆盖前两者，多个 `assign`
   时最后一个生效。条件中除以零的结果定义为 0。
4. **代价模式**：出现 `:action-costs`、`total-cost` 相关效果/初始赋值或
   引用 `total-cost` 的 `:metric` 时进入代价模式，动作基础代价为 0，由
   `increase (total-cost)` 累加；否则为经典单位代价。`total-cost` 只能被
   `increase`，且必须无条件（`when` 内的代价会被拒绝）；**动作代价表达式
   只能读取静态函数**（在 `:init` 赋值且无任何效果修改的函数）——这与
   Fast Downward 的处理一致，状态相关的代价会导致搜索目标不可静态确定。
   代价在内部用 `Double` 表示，整数代价精确到 2^53；单个动作与初始
   `total-cost` 上限为 10^12，累计代价达到 10^15 视为饱和。
5. **目标**同样编译为 DNF；命题部分查位集，数值部分读状态 fluent 数组。
   `total-cost` 不进入状态（它是路径代价 `g`），因此条件中出现 `total-cost`
   会被拒绝。
6. **metric** 的方向与表达式会被解析记录；搜索固定按代价（`total-cost`）
   最小化。`maximize` 任务仍会返回合法计划，但不优化最大化目标。
7. **数值精度**：fluent 值与代价用 IEEE 754 双精度存储；数值比较带 1e-9
   容差，状态键与输出把非常接近整数的值规范化为整数。整数与简单小数
   （0.5、3.25 等）全程精确。

## 架构

```text
PDDL 文本
   │  lexer.mbt + sexp.mbt
   ▼
S 表达式（带行列位置）
   │  parser.mbt → ast.mbt
   ▼
Domain / Problem
   │  ground.mbt（类型、对象、量词、DNF、条件效果、数值编译、静态代价、剪枝）
   ▼
GroundProblem（原子表 + fluent 表 + 位集/数组 State + 接地动作）
   ├── heuristics.mbt（删除松弛：hmax / hadd / hff）
   │        └── search.mbt（GBFS / A* / WA*）→ SearchResult → 计划文本
   └── validate.mbt（独立重放）→ ValidationReport（文本 / JSON）
```

| 文件 | 职责 |
| --- | --- |
| `lexer.mbt`、`sexp.mbt` | 词法与 S 表达式读取，记录源码位置 |
| `parser.mbt`、`ast.mbt` | PDDL 领域/问题解析与 AST（含数值表达式） |
| `error.mbt` | `PddlError`、错误分类与位置格式化 |
| `ground.mbt` | 类型层次、接地、DNF 编译、数值状态与效果、静态代价、可达性剪枝 |
| `heuristics.mbt` | 删除松弛任务、`hmax`、`hadd`、`hff`、目标计数 |
| `search.mbt` | 开放表、GBFS/A\*/WA\*、节点预算、计划重建 |
| `validate.mbt` | 计划文本解析、独立执行、诊断与 JSON 报告 |
| `cmd/moonpddl/` | 原生 CLI |

### 启发式与可采纳性

- `hmax` 在删除松弛上计算每个原子的最小达成代价并取目标最大值；在非负动作
  代价下可采纳。配合 `AStar` 得到最优计划。数值约束在松弛中丢弃——松弛任务
  是真实任务的放松，可采纳性保持。
- `hadd` 将目标代价求和，通常更有信息量但不可采纳。
- `hff` 在松弛任务上提取一条松弛计划并累加其代价，适合 GBFS/WA\*。
- `goal-count` 统计未满足目标字面量数（含数值约束）；`blind` 恒为 0。

## 示例

| 领域 | 规模 | 展示能力 | 计划代价 |
| --- | --- | --- | --- |
| [blocksworld](examples/blocksworld) | 3 个积木 | STRIPS、类型、最优搜索 | 4 |
| [gripper](examples/gripper) | 2 个球、2 个夹爪 | 多类型对象与移动 | 5 |
| [logistics](examples/logistics) | 2 城市、卡车 + 飞机 | 多交通工具、9 步计划 | 9 |
| [matchcellar](examples/matchcellar) | 2 根火柴、2 个保险丝 | 动作代价与 `:metric` | 4 |
| [delivery-numeric](examples/delivery-numeric) | 3 地点、1 卡车 | 数值 fluent、静态函数代价输入、数值前提与效果 | 34 |

每个目录都包含 `domain.pddl`、`problem.pddl` 与手工核对的 `plan.pddl`：

```bash
moon run --target native cmd/moonpddl -- validate \
  examples/delivery-numeric/domain.pddl examples/delivery-numeric/problem.pddl \
  examples/delivery-numeric/plan.pddl
# plan valid: 3 step(s), cost 34
```

## 测试与基准

```bash
moon test                     # 91 个测试，wasm
moon test --target native     # 同一套测试，native
moon test --include-skipped -f "benchmarks:*"   # 可选性能基准
```

测试中包含一个专门的符合性测试组（`conformance_wbtest.mbt`），逐条钉住上表
的 Level 1 语法与语义规则。

基准使用 `moonbitlang/core/bench`，在 blocksworld 夹具上测量解析、接地、搜索与
验证。以下是本机 wasm 调试构建的一次采样（10 次运行，单位为微秒，仅作量级
参考）：

| 阶段 | 中位耗时 |
| --- | --- |
| 解析领域 + 问题 | ≈ 108 µs |
| 接地（24 个动作，含剪枝） | ≈ 246 µs |
| GBFS + `hff` 求解 | ≈ 262 µs |
| 验证 4 步计划 | ≈ 33 µs |

CI（[.github/workflows/ci.yml](.github/workflows/ci.yml)）在 Ubuntu 上执行
`moon fmt --check`、`moon check --deny-warn`、wasm/native 双后端测试、原生 CLI
构建，并验证全部示例计划、最优求解 blocksworld 与 delivery-numeric。

## 限制与路线图

- 采用**完全接地**，动作数随对象数量组合增长；当前上限为 200,000 个接地动作、
  8,192 个 DNF 分支，公式/效果/数值表达式的嵌套深度上限为 256（超出报错而
  不是崩溃）。接地后有一遍删除松弛可达性剪枝，但没有基于相关性分析的
  接地期剪枝。
- 搜索为前向最佳优先；尚无语义剪枝、landmark、SAS+ 或符号搜索。
- PDDL 2.1 **Level 2 及以上**（durative actions、连续效果、PDDL+ 时态模型）与
  PDDL 2.2/3.x 扩展（派生谓词、timed initial literals、偏好、约束）不在
  符合性终点内，遇到时明确报错。
- 动作代价表达式只能读取静态函数（与 Fast Downward 一致）；状态相关代价会
  被明确拒绝。`maximize` metric 只记录不优化。
- GBFS 按启发式值 `h` 排序，不保证最优；需要最优解时使用可采纳的
  `hmax + A*`。
- 计划验证基于同一套接地语义；它会独立重放计划，但不会重新推导领域语义。

后续计划包括：接地相关性剪枝、landmark 启发式、计划后处理（去除冗余步骤）、
浏览器内 wasm 演示，以及 PDDL 2.2 派生谓词支持。

## 开发说明与 AI 使用披露

本项目在开发过程中使用了 AI 编程助手（Qoder、ZCode）协助代码实现、测试用例
设计、文档撰写与命令行调试。所有提交代码均经过本地 `moon check`、91 个测试、
wasm/native 双后端运行以及五个示例计划验证；作者对最终代码、设计与正确性负责。

欢迎提交 issue 与 PR。

## 许可证

[MIT](LICENSE)

## 参考

- D. McDermott et al., *PDDL — The Planning Domain Definition Language*.
- M. Fox and D. Long, *PDDL2.1: An Extension to PDDL for Expressing Planning
  Domains with Numeric Fluents*.
- J. Hoffmann and B. Nebel, *The FF Planning System: Fast Plan Generation
  Through Heuristic Search*, JAIR 2001.
- M. Helmert, *The Fast Downward Planning System*, JAIR 2006.
