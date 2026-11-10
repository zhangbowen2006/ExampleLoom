# 功能范围与参照系统

## v0.5 初审意见对应的实现

| 评审关注点 | 从样例能学到什么 | 可复现证据与边界 |
| --- | --- | --- |
| 条件分支 | 空值、枚举值、用户提示的正则或反复出现的字段形状都可用于划分。逐行搜索最多三层，表格行映射支持一层。两侧至少各有两个训练观察 | 工作台「混合编号展开」从训练数据学到展开标签、判断编号形状、抽取数字和拼接前缀。新输入 `ZZ9530`、`8042-NEW` 分别输出 `IN/9530`、`OUT/8042`。[示例](../examples/structures/mixed-tags.json) |
| 正则语义与学习 | 使用 MoonBit core 正则执行整串和局部匹配、捕获及全局替换。学习器从 ASCII 字母/数字段及字面分隔符生成模式，也可接受最多 16 个显式模式。在训练输出上同时匹配各捕获组，允许重排、重用组及转义字面 `$` | 「重排批次编号」在新输入 `PQR-00097/Q` 上得到 `Q:$00097/PQR`。530 项共同语法对照覆盖捕获、匹配与替换。PCRE 前后查找、模式内反向引用和任意正则生成超出当前范围。[示例](../examples/rewrite/scenario.json) |
| 表格结构与计算 | 22 类结构操作。新增按一个或多个键执行计数及 Int64 求和、最小值、最大值。可从多对输入输出一起学习多个指标，生成的 v2 管道能在新数据上重放 | 两批订单上学到按地区计数和汇总净额。在公开 IANA 数据上还学到了展开列表后再计数。十进制小数、自由编写的聚合函数和跨表连接仍在范围之外。[订单示例](../examples/structures/regional-totals.json) · [SQLite 对照](evidence/iana-counts-v0.5.0.json) |
| 外部工作负载 | 表格使用 Foofah 原测试集，字符串使用 SyGuS 公开 PBE 赛题。训练一致、首候选留出全对、事后候选上界和耗时分别计量 | 公开逐题成功、失败、截断、排除原因和引擎哈希。Foofah 任务已用于迭代开发。SyGuS 重复输入和相同拆分另计。[基准与复现命令](BENCHMARKS.md) |

Microsoft PROSE 提供面向自定义 DSL 的通用合成框架，允许实现者定义语义、逆向约束推导和排名。ExampleLoom 提供固定的 MoonBit 行表达式、结构算子和面向这些算子的学习算法。两者的功能交集包括从样例推导文本转换，当前 ExampleLoom 的公开接口只允许组合内置算子。[Microsoft 官方教程](https://www.microsoft.com/en-us/research/project/prose-framework/tutorial/)

Foofah 在整表输入输出上搜索清洗程序。其源码提供按列拼接、填充、按固定行数重组等操作，ExampleLoom 与它在这些任务上有实质重叠。这里可核验的交付包括独立浏览器工作台、按名称绑定的 JSON 管道、结构化的正则行映射和多指标分组。两套上游系统的整机速度没有在本次环境中同机测量。[Foofah 算子源码](https://github.com/umich-dbgroup/foofah/blob/970864cd53b4c774a3dbdf4589d207f57ec63208/foofah_libs/operators.py) · [ExampleLoom 协议](PROTOCOL.md)

本项目沿用 ExampleLoom 的仓库和历史，核心搜索与运算由 MoonBit 实现。其他相邻项目及依赖来源见[项目调研](RESEARCH.md)。

## 可以复现的三个完整场景

1. 供应商运营整理混合格式编码：输入 `examples/conditional/input.csv`，前四行分别示范 local/global 的正确输出，搜索并选用条件程序，后两行得到 `CN/0777`、`INT/45001`。自动化验证训练和留出所有值，浏览器检查真实 `If` 程序。
2. 运维人员提取带噪声记录中的 ref：输入 `examples/regex/input.csv`，给两行答案与 `ref=([[:digit:]]+)` 提示，选用捕获规则，另两行得到 `70004`、`001234`，不能拿其他数字替代。API 和浏览器都要求实际首候选为 `capture`。
3. 财务运营向分析系统输出长表：按 `examples/structures/unpivot.json` 提供 A/B 宽表和目标长表，学习 Unpivot 管道，输入列重排后的 C/D 新表，得到四条月份记录，保留前导零、零值和空格。验证保存/重载、CLI 全流程、浏览器整表下载和所有输出值。

另外提供连续行打包、原始网格 Melt 的完整流程。上述业务演示为构造数据；外部任务不是这些演示的变体。尚无客户部署、用户采用或业务收益证据。


## v0.4 新增可复现流程

- `examples/structures/dynamic-pivot.json`：监测开发者把长表还原为原始网格；下一批新增 pressure 类别，按实际数据产生新列，并保留零与空单元格。
- `examples/structures/header-details.json`：运营人员把每个表头的编号与名称传播到明细；新表头替换上下文，首个表头前出现明细则报错。
- `examples/structures/labelled-grid.json`：分析人员把 low:007 等单元格还原为网格，组合 Fold → SplitColumn → PivotGrid；下一批标签变化仍可运行。

这些独立业务流程及前述场景均通过 API/CLI/真实浏览器验证；仍为构造数据，不声称客户采用。pandas 差分验证与外部 Foofah 任务分开报告。
