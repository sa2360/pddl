# moonpddl 参赛申报书

**赛事**：2026 MoonBit 黑客松（MoonBit 开源大赛·十月黑客松）  
**项目名**：moonpddl — PDDL 规划引擎与独立计划验证器  
**仓库**：<https://github.com/sa2360/pddl>  
**Mooncakes 模块**：`sa2360/pddl`  
**版本**：0.1.0  
**日期**：2026-10-21  
**许可证**：MIT

## 一、项目一句话简介

moonpddl 用 MoonBit 实现了从 PDDL 文本解析、类型化接地、删除松弛启发式、
前向状态空间搜索到独立计划验证的完整经典规划流水线，并提供带 JSON 输出的原生
CLI、可运行示例、测试与基准。

## 二、选题背景与生态价值

PDDL（Planning Domain Definition Language）是经典人工智能规划的标准建模语言，
被国际规划竞赛（IPC）和大量规划研究、教学课程采用。一个可用的 PDDL 工具链
需要同时解决：

1. 带类型层次、量词、否定与析取的一阶逻辑公式解析与编译；
2. 条件效果、负前提、动作代价等扩展语义的接地；
3. 可采纳启发式与前向搜索；
4. 与求解器解耦、能定位到源码位置的计划验证。

在 MoonBit 生态中，这些能力此前没有对应实现。截至 2026-10-21，在
mooncakes.io 上未检索到 PDDL 规划器或计划验证器包。moonpddl 不是对已有
MoonBit 包的重复封装，而是将经典规划这一完整应用领域带入 MoonBit，并可作为
AI 规划教学、算法对照实验与工具链集成的开源基础设施。

与常见的解析器、序列化库相比，本项目覆盖“语言前端 + 编译 + 启发式 + 搜索 +
验证 + CLI”全链路，技术纵深和可演示性更强。

## 三、与上次提交《moonbit-toml》的区别

上次提交的 TOML 库未通过初审，核心原因是
`moonbit-community/toml@0.5.0` 已经成熟且下载量高，选题存在明显重复。本项目
在两个层面做了根本调整：

1. **领域不同**：从通用数据格式解析转向经典 AI 规划。mooncakes.io 上没有
   PDDL 规划/验证包，不存在同质化竞争。
2. **项目类型不同**：TOML 项目是单一格式的解析/序列化库；moonpddl 是包含
   解析器、编译器、启发式、搜索器、验证器和 CLI 的系统性工程，其中计划
   验证器与求解器相互独立，具备更强的研究与应用价值。

## 四、交付物

| 交付物 | 位置 | 说明 |
| --- | --- | --- |
| 核心库 | 仓库根包 `sa2360/pddl` | 解析、接地、启发式、搜索、验证 API |
| 原生 CLI | `cmd/moonpddl/` | `solve` / `validate` / `check` / `ground` / `version` |
| 示例 | `examples/` | blocksworld、gripper、logistics、matchcellar，各含领域、问题与计划 |
| 测试 | 根包 `*_test.mbt` | 41 个单元/集成测试，wasm 与 native 双后端通过 |
| 基准 | `bench_test.mbt` | 解析、接地、求解、验证四个阶段，使用 core/bench |
| 文档 | `README.md`、`README.en.md` | 中英文使用文档、支持子集、语义与架构 |
| CI | `.github/workflows/ci.yml` | 格式、检查、双后端测试、CLI 构建、示例验证 |

## 五、技术实现

### 5.1 语言前端

- 手写词法分析与 S 表达式解析，所有节点记录行列位置；
- PDDL 领域/问题解析为强类型 AST；
- 错误分为语法错误、未支持构造与模型不一致三类，携带位置并实现 `Show`；
- 对不支持的需求标记和结构显式报错，避免静默忽略导致错误语义。

支持的需求标记包括 `:strips`、`:typing`、`:negative-preconditions`、
`:disjunctive-preconditions`、`:equality`、`:existential-preconditions`、
`:universal-preconditions`、`:conditional-effects`、`:action-costs`、`:adl`。

### 5.2 类型化接地

- 构建单继承类型层次，按父类型检查对象与参数兼容性；
- 合并领域常量与问题对象，检测重复声明；
- 将前提条件与目标编译为 DNF，支持嵌套量词展开；
- 将条件效果按“前提分支 × 效果条件分支”因式分解为独立接地效果；
- 使用位集（`Array[Int]`）表示状态，支持高效的适用性判断与后继计算；
- 对 DNF 分支数（8,192）与接地动作数（200,000）设置显式上限，防止组合爆炸
  导致不可控内存占用。

### 5.3 启发式

在删除松弛任务上实现：

- `hmax`：逐原子最小达成代价，目标取最大值；非负代价下可采纳；
- `hadd`：目标代价求和，信息量更强但不可采纳；
- `hff`：贪心提取一条松弛计划并累加动作代价；
- `goal-count`：未满足目标字面量计数；
- `blind`：零估计。

启发式按搜索任务缓存删除松弛结构，避免每个状态重复构建。

### 5.4 搜索

- GBFS、A\*、加权 A\*（可配置权重）；
- 自定义二叉最小堆，比较键为 `f`、`h`、`g`、插入顺序；
- `best-g` 表去重，A\* 在发现更优路径时重新打开节点，保证可采纳启发式下的
  最优性；
- 扩展数与生成数上限，返回 `Solved`、`Exhausted`、`NodeLimitReached` 三种
  终止状态；
- 计划通过父节点链重建，代价包含问题初始 `total-cost`。

### 5.5 独立计划验证器

- 计划文本支持可选括号、大小写不敏感、行内 `;` 注释与 `; cost = N` 标注；
- 独立于搜索过程，逐步检查动作存在性、参数合法性、前提可满足性；
- 未达成目标时给出最近一步的未满足 DNF 分支摘要；
- 代价标注不一致作为警告，不改变计划可执行性结论；
- 报告可序列化为 JSON，包含 `valid`、`steps`、`executed`、`cost`、
  `declared_cost` 与结构化 `issues`（含行号、步骤号、类别）。

### 5.6 CLI

- `solve`：支持策略、启发式、权重、扩展上限、JSON、计划写文件、静默模式；
- `validate`：逐行诊断与 JSON 报告；
- `check`：展示领域/问题摘要与代价模式；
- `ground`：列出全部接地动作及代价；
- 退出码固定为 0/1/2，便于脚本与 CI 使用。

## 六、可复现验证

以下结果均在本仓库当前代码上实际执行得到：

```text
$ moon check --deny-warn
Finished, 0 warnings

$ moon test
Total tests: 41, passed: 41, failed: 0

$ moon test --target native
Total tests: 41, passed: 41, failed: 0
```

四个示例计划全部通过独立验证：

```text
examples/blocksworld/  plan valid: 4 step(s), cost 4
examples/gripper/      plan valid: 5 step(s), cost 5
examples/logistics/    plan valid: 9 step(s), cost 9
examples/matchcellar/  plan valid: 4 step(s), cost 4
```

最优性验证：blocksworld 在 `--search astar --heuristic hmax` 下得到代价 4 的
计划，与手工最优解一致；A\* 在该领域只扩展 6 个状态。

性能基准（本机 wasm 调试构建，10 次采样，中位值，仅作量级参考）：

| 阶段 | 中位耗时 |
| --- | --- |
| 解析领域 + 问题 | ≈ 116 µs |
| 接地（3 个对象、24 个动作） | ≈ 188 µs |
| GBFS + `hff` 求解 | ≈ 248 µs |
| 验证 4 步计划 | ≈ 22 µs |

复现命令：

```bash
moon test
moon test --target native
moon build --target native cmd/moonpddl
./_build/native/debug/build/cmd/moonpddl/moonpddl validate \
  examples/blocksworld/domain.pddl examples/blocksworld/problem.pddl \
  examples/blocksworld/plan.pddl
moon test --include-skipped -f "benchmarks:*"
```

## 七、创新点与亮点

1. **完整规划闭环**：在同一 MoonBit 模块内完成解析、接地、启发式、搜索、
   验证，而非只做 PDDL 语法解析。
2. **可采纳启发式与最优性**：`hmax` + A\* 在非负代价下给出最优计划，并有
   测试覆盖。
3. **独立验证器**：计划验证不依赖搜索轨迹，可验证外部生成的计划，适合作为
   规划课程作业与竞赛计划的自动评分工具。
4. **结构化诊断**：解析错误带行列位置，验证错误带计划行号与步骤号，JSON
   输出便于工具集成。
5. **工程完备性**：示例、测试、基准、CI、双语文档与 AI 使用披露齐备，可
   直接作为 MoonBit 教学与生态示例。

## 八、已知限制

- 采用完全接地，规模受对象数量组合增长限制；
- 仅支持 `total-cost` 数值模型，不支持 durative actions 与 PDDL+；
- 尚未实现可达性剪枝、landmark 启发式与 SAS+ 编译；
- 验证器与规划器共享接地语义，不是完全独立的形式化语义实现。

这些限制已在 README 中明确说明，并列入后续路线图。

## 九、AI 辅助开发声明

本项目在开发过程中使用 AI 编程助手（Qoder）协助：代码实现、测试用例设计、
文档撰写、CLI 调试与提交材料整理。所有代码均经过本地编译、测试、双后端运行
与示例验证；项目作者对最终设计、代码正确性与开源合规负责。项目未复制其他
规划器的源代码，算法实现参考公开论文与 PDDL 规范。

## 十、后续计划

- 基于可达性的接地剪枝与静态不可达动作剔除；
- landmark 启发式与更高效的状态压缩；
- 计划后处理（去除冗余步骤、计划长度优化）；
- 浏览器内 wasm 演示与可视化；
- 扩展 PDDL 3 约束与更多数值模型。

## 十一、链接

- 仓库：<https://github.com/sa2360/pddl>
- 模块：`sa2360/pddl`（mooncakes.io）
- 许可证：[MIT](../LICENSE)
