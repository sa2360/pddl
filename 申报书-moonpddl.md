# moonpddl 项目申报书

## 基本信息

- 项目名称：moonpddl —— 基于 MoonBit 的 PDDL 2.1 Level 1 规划与计划验证工具
- 参赛者：sa2360
- 联系方式：GitHub:sa2360 qq邮箱:2360682759@qq.com
- GitHub 仓库链接：https://github.com/sa2360/pddl
- 项目方向：MoonBit 经典 AI 规划 / 规划算法与验证工具
- 是否为移植项目：否

## 项目简介

这次想做一个能真正“算”出结果的工具，而不是再写一个数据格式的读写库。PDDL 是经典规划领域的标准建模语言，国际规划竞赛和不少人工智能课程都会用到；它的好处是领域模型和求解算法分得比较开，同一份领域文件可以换不同的策略来跑。

选题前我查了 mooncakes.io，截至 2026 年 10 月没有找到 PDDL 规划器或计划验证器相关的包。MoonBit 生态里已经有 JSON、TOML 这类成熟的解析库，但规划方向还是空的，所以我把题目定为“PDDL 规划引擎 + 独立计划验证器”。

## 符合性终点（对应上一轮初审意见）

上一轮初审指出：申报只写了“常用子集”，没有确立明确的 PDDL 标准级别作为完整符合终点，而且动作代价不接受规范允许的静态函数输入，影响既有模型复用。这轮我针对这两点把范围收严、把功能补齐：

**本项目的符合性终点是：PDDL 2.1 Level 1（经典规划 + 数值 fluent）的完整语法与语义，外加 PDDL 3.1 的 `:action-costs` 需求标记。** Level 2 及以上（durative actions、连续效果、PDDL+ 时态模型）不在范围内，遇到时明确报错并给出行列位置，而不是静默忽略。这个终点是可检验的：README 里有一张对照 PDDL 2.1 Level 1 语法的逐项覆盖表，测试里有一个专门的符合性测试组（`conformance_wbtest.mbt`）逐条钉住每一行。

关于动作代价：现在代价表达式支持规范允许的**静态函数输入**，也就是在 `:init` 里赋值、没有任何效果修改的函数。比如 `(increase (total-cost) (* (fuel-price) (distance ?from ?to)))` 可以直接声明在领域里，`fuel-price` 和 `distance` 都是静态函数，每个接地动作的代价在接地期按初值精确求值。这正是 Fast Downward 对动作代价的处理方式，也是既有 IPC 代价模型复用时最常用到的形态。仓库里的 `examples/delivery-numeric/` 就是一个完整示例：油量、距离、油价都是 `:functions` 声明的数值 fluent，A\* + hmax 求出代价 34 的最优计划，验证器复核一致。

## 核心功能范围

项目已经能跑通从读文件到出计划、再到验证计划的完整流程：

- PDDL 解析：覆盖 Level 1 全部需求标记（`:strips`、`:typing`、`:negative-preconditions`、`:disjunctive-preconditions`、`:equality`、`:existential-preconditions`、`:universal-preconditions`、`:quantified-preconditions`、`:conditional-effects`、`:fluents`、`:adl`、`:action-costs`）。类型系统支持多继承的 `(either ...)`；公式支持任意嵌套的连接词、量词、对象相等和五种数值比较。
- 数值引擎（本轮新增）：任意 0 元/多元函数声明（参数带类型）、整数与实数字面量、`+ - * /` 与一元负号任意嵌套、五种数值比较出现在前提/效果条件/目标、`increase`/`decrease`/`assign`/`scale-up`/`scale-down` 五种数值效果、`:init` 对任意函数赋值（支持负数和小数）、`:metric minimize/maximize` 作用于完整表达式。
- 接地：类型继承（含 either 并集语义）、领域常量和问题对象合并、参数类型检查、量词展开、公式 DNF 编译、条件效果分支拆分、数值表达式编译成带 fluent 引用的求值树，以及删除松弛可达性剪枝（把“前提永远无法满足”的接地动作剔除，是过近似，不会漏掉可用动作）。
- 启发式：blind、goal-count、hmax、hadd、hff 五种。hmax 在删除松弛上计算，动作代价非负时可采纳；数值约束在松弛中被丢弃，所以可采纳性对真实任务依然成立。
- 搜索：GBFS、A\*、加权 A\* 三种策略，二叉堆是自己写的，支持按 g 值去重、A\* 发现更短路径时重新打开节点，也能设置扩展数上限；数值 fluent 的值参与状态去重，同一批原子不同油量的状态不会被合并。
- 计划验证：验证器不依赖搜索过程，会重新解析计划文本并逐步执行，报告未知动作、参数错误、前提不满足（未满足的数值前提会原样渲染出来，比如 `(>= (fuel t1) 9)`）、目标未达成，以及计划里 `; cost = N`（支持小数）和实际代价不一致的问题。
- 命令行和示例：solve、validate、check、ground 四个子命令，支持 JSON 输出、计划写文件和固定退出码；仓库里有 blocksworld、gripper、logistics、matchcellar、delivery-numeric 五个可直接运行的例子。

## 实现思路

整个流程是：先把 PDDL 文本解析成 S 表达式，再转成领域和问题的结构；然后接地成具体的动作、原子和 fluent，状态用位集加一个双精度数组表示；搜索时在删除松弛任务上算启发式，最后根据父节点链把计划还原出来。

有几个地方我印象比较深：

- 条件效果的条件一定要在执行动作前的状态上判断。删除和添加也要先一起收集，最后先删后加、添加优先。数值效果我定义了同样的“同时语义”：右端全部按执行前状态求值，同一函数上 increase/decrease 先求代数和，再按出现顺序 scale，assign 最后覆盖。
- `total-cost` 我特意没有放进状态里。它是路径代价 g，放进状态会让每个状态因代价不同而无法去重，搜索直接退化。所以前提/目标里出现 `(total-cost)` 会被明确拒绝，初始赋值和 metric 单独走代价通道。
- 动作代价只允许读静态函数（初始化后不再改变的函数），状态相关的代价会在接地期被明确拒绝。这不是偷懒：代价一旦依赖运行时状态，搜索目标就没法静态确定，Fast Downward 也是同样处理。
- DNF 展开和接地动作数都可能增长得很快，所以我加了上限：8192 个 DNF 分支、20 万个接地动作，超过就明确报错。接地之后还有一遍松弛可达性剪枝，第一版测试里它把相等判断域里 “(not (= a a))” 这种永远不可满足的接地动作剔掉了。
- 数值表示这块我权衡过定点和浮点，最后选了双精度：整数和 0.5、3.25 这类简单小数全程精确，比较带 1e-9 容差，状态键把非常接近整数的值规范化，避免链式算术把同一个状态拆成多个键。单个动作代价和初始 total-cost 上限 10^12，累计到 10^15 视为饱和，所有中间和都落在双精度整数精确区内。
- MoonBit 的 `Int` 是 32 位，所以早期版本溢出过；这一版代价统一走 `Double`，之前的 30 亿、42 亿多、两次 6 亿的测试用例全部保留，另外补了小数代价的用例。
- A\* 只有在启发式可采纳时才保证最优，所以默认的 hff 配 A\* 并不保证最优。文档里把这一点写明了；想要最优解可以用 `hmax + astar`。

做完之后我最大的感受还是那句话：麻烦的不是把 A\* 写出来，而是把 PDDL 的语义准确地落到接地动作上。所以我坚持把验证器单独拆出来，让它不经过搜索，直接把计划拿来重新执行一遍。数值功能加进来之后这套设计帮了大忙：搜索出的计划和手算的代价只要有一点偏差，验证器立刻就能抓出来。

## 目前完成情况

本地 `moon check --deny-warn` 没有警告，`moon test` 在 wasm 和 native 两个后端都是 86 个测试全部通过，其中包含一个专门的 PDDL 2.1 Level 1 符合性测试组。五个示例计划都能通过验证：

```text
examples/blocksworld/       plan valid: 4 step(s), cost 4
examples/delivery-numeric/  plan valid: 3 step(s), cost 34
examples/gripper/           plan valid: 5 step(s), cost 5
examples/logistics/         plan valid: 9 step(s), cost 9
examples/matchcellar/       plan valid: 4 step(s), cost 4
```

用 `solve --search astar --heuristic hmax` 跑 blocksworld 得到代价 4 的最优计划；跑 delivery-numeric 得到代价 34 的最优计划（加油 20 + 两段行驶 8 + 6），和手算一致。仓库里还有一个基准测试，分别测解析、接地、求解和验证；在本机 wasm 调试构建下，GBFS + hff 求解 3 个积木的 blocksworld 大约 0.26 毫秒。这个数字只能说明小例子上的开销，不能代表大规模问题的性能。

## 原创性与参考说明

本项目不是移植，也没有复用其他规划器的代码。PDDL 是公开的语言规范，我参考了 McDermott 等人的 PDDL 文档、Fox & Long 的 PDDL2.1 规范，以及 FF、Fast Downward 两篇论文中关于删除松弛和启发式搜索的思路；动作代价“只读静态函数”的取舍参考了 Fast Downward 的实现约定。解析、接地、数值引擎、搜索和验证的代码都是重新写的。

核心库只依赖 MoonBit 标准库；命令行用 `moonbitlang/x` 读取文件和设置退出码。项目使用 MIT 许可证。

## AI 工具使用说明

开发过程中我用了 AI 编程助手（Qoder、ZCode）辅助实现代码、查 MoonBit 语法、补测试和整理文档。MoonBit 在错误类型、循环写法、字符串切片这些地方和我以前学的语言不太一样，有 AI 帮忙确实省了不少翻文档的时间。

不过功能能不能跑，我还是以本地结果为准：每个子命令都实际执行过，测试和五个示例计划也都跑过，不是只看代码“看起来对”。AI 能帮忙写和改，但最后对不对，还是得我自己看结果。

## 不足和后续计划

- 现在是完全接地加一遍松弛可达性剪枝，动作数量仍会随对象数量组合增长，还没有做基于相关性分析的接地期剪枝。
- PDDL 2.1 Level 2 及以上（durative action、连续效果、PDDL+）和 2.2/3.x 扩展（派生谓词、timed initial literals、偏好、约束）不在符合性终点内，遇到会明确报错。
- `maximize` metric 目前只记录不优化；搜索固定按 total-cost 最小化。
- 启发式只做到了删除松弛这一层，还没有 landmark、SAS+ 这些。
- 验证器和规划器共用同一套接地语义，虽然能独立重放计划，但还不是另一套完全独立的形式化实现。

截止日期前，我主要会把文档和示例再检查一遍，补一些边界测试，确保 CI 和本地结果一致。再往后想加接地相关性剪枝、landmark 启发式、计划后处理、PDDL 2.2 派生谓词，以及一个能在浏览器里直接跑的 wasm 演示。

## 链接

- 仓库：https://github.com/sa2360/pddl
- Mooncakes 模块：https://mooncakes.io/docs/sa2360/pddl
- 使用文档与符合性对照表：[README.md](README.md)
- 示例目录：[examples/](examples/)
