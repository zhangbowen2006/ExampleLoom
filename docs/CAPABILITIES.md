# v0.4 功能对比与实现范围

这是工程事实与差距说明，不是通过初审或获奖承诺。ExampleLoom 延续原仓库和开发历史，修正上一轮驳回指出的能力缺失，不作为换名的新作品。

| 能力 | 本次可执行实现 | 当前自动学习范围 |
| --- | --- | --- |
| 条件分支 | `If`、相等、空值、正则谓词、Not/All/Any；短路执行 | 平直规则无解后，按空值、提供的模式、低基数字段值划分，最多 3 层；两侧各至少 2 样例；不学习任意复合谓词 |
| 正则上下文 | MoonBit core 的动态模式、搜索/整串匹配、捕获和全局替换；Unicode、空匹配正常推进 | 用户最多 16 模式提示；枚举组 0–4、出现位置 0/1/-1；新增共享字面上下文 + ASCII 类捕获推断及固定分隔符替换见证；仍不推断任意模式或模板 |
| 表格结构 | 选择/重命名、过滤、行映射、拆列、单元格展开、Unpivot/Fold/Melt/Pivot、连续行打包、分组展开、转置、表头升降、向下填充、去重、丢弃前行，另增动态网格透视、列合并、记录分段及表头传播，共 21 类操作 | 多对完整小表约束下的有界结构搜索；默认 4 步/128 状态/2000 次原始算子预算；最佳优先、8 路局部保留和有限组合见证，不是完备搜索。键列主要枚举前缀组合；不能穷举全部列子集 |
| 数据导出 | v1 逐行配方、v2 结构管道、CSV/JSONL、命名列重绑定、浏览器 Worker 与 CLI | 人工明确选择候选；排名是启发式，不表示置信度 |
| 外部评估 | 完整上游 250 个 Foofah 任务，50 类任务族；训练表与上游测试表分开 | 25 个测试答案占位任务单列；225 个有答案任务计成功率，全部 250 个保留在总表，错误和超时不按结果删除 |

## 与参考系统比较

| 系统与一手来源 | 核心能力、运行约束 | ExampleLoom 已验证的区别与不足 |
| --- | --- | --- |
| [PROSE SDK](https://github.com/microsoft/prose)、[官方技术教程](https://www.microsoft.com/en-us/research/project/prose-framework/tutorial/) | 可自定义 DSL、语义、witness functions 和排名的程序合成框架；SDK 与示例使用 .NET/C# | 本项目独立实现 MoonBit 解释器和有界搜索，浏览器不需要 SDK/.NET；未实现通用 witness-function 框架、完整 VSA 或 PROSE 的日期/数值/语义合成覆盖，不能声称性能或能力超过 PROSE |
| [Foofah 主仓库](https://github.com/umich-dbgroup/foofah)（MIT） | 以表格输入输出为约束合成结构转换程序；原仓库列出 Linux、Python 2.7、g++/Boost.Python 等要求 | 本项目可在浏览器 Worker 本地搜索并导出可重用 JSON 程序，Node 无 npm 运行依赖；独立实现且实际运行上游测试数据，但仍不支持完整操作/参数空间，也没有运行 Foofah 本体的同机性能对照 |
| [MoonBit core 正则](https://github.com/moonbitlang/core/tree/main/string)、[lexmatch 规格](https://github.com/moonbitlang/lexmatch_spec)（Apache-2.0） | 提供现成匹配引擎与语法 | 本项目复用官方引擎，不把正则引擎算作原创；新增工作是 AST/配方集成、捕获候选枚举、分支谓词、错误与资源边界以及工作台 |
| [MoonFrame](https://github.com/ihb2032/MoonFrame)、[moon-databridge](https://github.com/btlqql/moon-databridge) | MoonBit 生态已有显式表格计算、转换或数据处理项目，具体覆盖见其当前文档 | 本项目以输入输出约束到程序搜索为主；CSV 和表格算子本身不是独有创新，不宣称这些项目没有同类能力 |

只进行了功能、部署方式和源码文档层面的比较。没有安装运行 PROSE/Foofah 本体，不能据此填写二者的成功率、耗时、迁移收益或排名。

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
