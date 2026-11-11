# 选题与来源核对（2026-11-11 更新）

这是技术调研记录，不是参赛申报书。实现代码由 AI 辅助编写，维护者需理解、验证并负责。

v0.8 正则子系统直接采用并修改 [moonbitlang/regexp.mbt](https://github.com/moonbitlang/regexp.mbt) 的 Mooncakes 0.3.7（Apache-2.0），不再把所有正则实现描述为独立原创。包括解析器、AST、Unicode 表及 VM；新增断言、绝对位置匹配、共享执行预算、重复捕获重置与边界修复。[上游包哈希及修改清单](../LICENSES/moonbit-regexp.NOTICE) · [详细语义与范围](REGEX_PROFILE.md)。其余搜索、表格结构、配方、工作台和 CLI 沿用项目实现；PROSE 与 Foofah 没有作为引擎依赖。

## 独立价值与范围

目标使用者是需要重复整理产品编号、活动名单和素材目录，但不想逐行处理或手写表达式的人。应用独立提供数据导入、样例编辑、程序搜索、分歧预览、配方保存和批量导出；不依赖旧项目、Excel、PROSE、云模型或专用服务端。可复用 MoonBit 库是同一核心的另一使用方式。

第一版聚焦逐行字符串转换。v0.3 在同一仓库补充条件、正则和有界表格结构合成，具体执行/学习范围与成熟系统差距见 [CAPABILITIES.md](CAPABILITIES.md)。不承诺任意转换或自然语言编程。竞争优势需要以运行效果和后续真实用户验证建立，不能由“MoonBit 重写”或不同名字推断。

## 已查证的最接近项目

| 来源 | 已有能力 | 本项目范围与差别 |
| --- | --- | --- |
| [MoonFrame](https://github.com/ihb2032/MoonFrame) | DataFrame、显式表达式、分组与连接 | 我们关注输入输出样例到程序的搜索；不替代其表格计算覆盖范围 |
| [moon-databridge](https://github.com/btlqql/moon-databridge) | 显式配置的导入、校验、转换、聚合 | 我们从样例推导候选，展示分歧，不以 CSV 清洗本身作为创新 |
| [Excel Flash Fill](https://support.microsoft.com/en-gb/excel/using-flash-fill-in-excel) | 从样例推断字符串分离、组合等 | 已有成熟同类需求解决方案；我们的贡献在开放可嵌入实现、显式候选和可移植程序，不是发明自动填充 |
| [PROSE](https://github.com/microsoft/prose) / [官方用法](https://www.microsoft.com/en-us/research/project/prose-framework/usage/) | DSL、程序集搜索、排名；Flash Fill 系列技术 | 概念参考，不调用 SDK、不复制实现，不声称程序合成或交互消歧首创 |
| [Foofah](https://github.com/umich-dbgroup/foofah)（MIT） | 从样例合成表格转换程序，包含表格结构变换 | v0.3 新增独立 MoonBit 表格算子和搜索，复用其许可内的全部 250 个任务做评估；仍未覆盖其完整操作与搜索空间，不声称功能或性能更全面 |

2026-11-02 查询 Mooncakes `/api/v0/modules` 返回 3533 条模块记录；在名称、描述与关键词搜索 flashfill、program synthesis、programming by example、示例驱动、程序合成、exampleloom 未发现直接同类条目。该结果仅为元数据检索，不证明不存在竞品。前次 GitHub / MoonBit 社区检索亦未找到已验证的直接同类，后续仍需跟踪。

## 与既有工作的关系

维护者既有 WasmSlim、MoonGate、AgentCanary、MoonBitTargetParity、MoonKeyguard、MoonBVHKit、BoxRIR、NeedleRail 等项目与本项目的核心用途不同。本项目使用新目录和新历史，不导入其业务代码。AgentCanary 是策略回放/回归工具，未被当作已驳回项目。其他参赛者的 TideWeave、HarborCheck 等仅作为避免边界不完整和未披露重叠的教训。

## 许可证与实现来源

ExampleLoom：MIT。运行时基础库 `moonbitlang/core`：Apache-2.0（以工具链附带许可证为准），v0.3 正则调用官方 core/string 引擎。合成及歧义选择采用已有领域思想，由本项目独立编写有限 DSL、搜索、解释器和工程接口；未移植 PROSE/Foofah 源码。v0.1 测试数据为构造数据；v0.2 增加 IANA、Unicode CLDR、github/gitignore 公开记录，分别为公共领域、Unicode-3.0、CC0-1.0，详见 fixtures/public/README.md。v0.3 新增 Foofah 主仓库 MIT 许可范围内的 250 个上游原始任务，详见 fixtures/foofah/README.md 与文件哈希清单。均不是客户采用证据。

## 赛事口径

[当前报名表](https://bxup9uklfcb.feishu.cn/share/base/form/shrcnWUMlgpbwHaXgzV7HmNhNhg) 已显示 11 月：可提交三次、重复修改；新项目季度赛道要求一页以内 Markdown、本人撰写且不要使用 AI、至少三个完整预期场景、公开仓库至少十个有效提交。提交数与既有报名的剩余名额需要本人在表单查看记录确认。

[官网](https://moonbitlang.github.io/Hackathon2026/)于 2026-11-11 实际加载的页面已显示十一月，报名时间以通过审核前最后一次有效提交或修改为准，未通过项目可修改。页面将报名与验收截止标为以官方通知为准，没有给出可确认的具体日期。十一月确切截止、当前账号剩余名额、Mooncakes 发布的最新强制口径仍待官方确认。正式提交由参赛者本人完成；本轮实际展开报名表的新项目季度选项后，仍看到本人撰写、不要使用 AI 的一页 Markdown 要求。本仓库只整理技术事实与核验材料，不代替本人提交。


## v0.4 补充核对

本次独立扩展 4 类算子、有限自动正则上下文与组合结构搜索，没有移植 Foofah/PROSE 源码。Foofah 测试数据中的 25 份 TestAnswer 为字面占位 `NOT AVAILABLE, SORRY`，需单列而不是视作模型预测错误；原始文件及 v0.3 历史记录保留。新的比较同时保留任务总数、有效答案分母和所有回退案例，不利用测试答案挑选首候选。

差分验证调用 [pandas](https://github.com/pandas-dev/pandas) 的 pivot、melt、groupby、ffill、concat 等成熟实现，输入与输出为本项目构造的随机表。pandas 仅在验证环境运行，不构成业务引擎依赖；不能把该构造验证称为新的独立外部盲测。实测与复现见 BENCHMARKS、VALIDATION。

## v0.6.1 维护调研（2026-11-11）

| 已查证的来源与许可 | 可以借鉴的地方 | 本轮采用范围 |
| --- | --- | --- |
| [microsoft/prose](https://github.com/microsoft/prose)，仓库样例 [MIT](https://github.com/microsoft/prose/blob/main/LICENSE)；SDK 二进制另受其许可约束 | [交互文档](https://www.microsoft.com/en-us/research/project/prose-framework/interactivity/)将候选运行、结果检查和有区分力的新样例纳入学习过程 | 独立实现表格候选的完整预测分组、差异位置和手工补样。没有引入 SDK、复用源码或声称该思路首创。其 README 说明自 2025-10-14 停止发布新 SDK 版本，不能称其为当前持续发布的依赖 |
| [Foofah](https://github.com/umich-dbgroup/foofah)，MIT | 保留整表结构语义，对新输入重放可执行程序 | 沿用许可内的完整任务集，另外在两道首候选失败的原题上核验新比较接口。搜索算子、预算和评分方法未改变 |
| [OpenRefine](https://github.com/OpenRefine/OpenRefine)，BSD-3-Clause | [操作历史导出和重用](https://openrefine.org/docs/manual/exporting)将一次数据处理变成可重复执行的工作流 | 保留本项目已有的版本化管道，补样后重新学习并序列化，在第三批数据上验证。没有复制历史系统、引入 Java 服务或声称等价覆盖其能力 |
| [MoonFrame](https://github.com/ihb2032/MoonFrame)、[moon-databridge](https://github.com/btlqql/moon-databridge)，均为 Apache-2.0 | 可参照其显式表格计算与转换的接口范围 | 保持样例到程序的学习和交互消歧定位；不把相同的 CSV、分组或转换能力单独当作差异，也未将其纳为运行时依赖 |

这里采用的是公开方法与交互思想。本项目的库、浏览器工作台和 CLI 仍独立运行。没有更换项目名、另建重复仓库、扩大“任意数据转换”承诺或更改外部评测分母。能否通过初审仍需组委会根据当前范围和实际材料判断。

## v0.7 范围补齐

本轮重新核对上述仓库、OpenRefine 的排序说明和 PROSE 公共任务分类，逐项区分覆盖与缺口，记录于 [GAP_ANALYSIS](GAP_ANALYSIS.md)。选择补齐可学习的稳定排序，独立实现比较器、训练置换/单调约束见证、管道编码和浏览器流程；没有复制参考项目代码或增加它们的运行时依赖。23 类操作与有限学习范围不等于完整 DataFrame、PROSE 或 OpenRefine。
