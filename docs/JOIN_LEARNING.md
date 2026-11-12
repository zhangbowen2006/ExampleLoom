# 从示例学习多表关联（v0.14）

本次针对评委指出的“通用数据转换能力不足”继续在原项目开发。新增的是**有限的多表连接任务搜索**：给出两个命名源表和期望输出，搜索连接键、连接类型及一个后续变换，生成可保存的 DataJob。不是任意 SQL 或多源程序合成；已有显式配置的任务仍可独立使用。

## 使用方式

[多表关联工作台](https://zhangbowen2006.github.io/ExampleLoom/join.html)提供两个构造案例，运行完全在浏览器 Worker 本地执行：

1. **商品与仓库双键**：两批输入展示行序、列序和未匹配情形。学习 SKU + 仓库的左连接及选列；第三批输出有匹配与未匹配商品。
2. **连接后精确汇总**：示范两批订单和商品目录及分类总额；学习连接与按分类的精确小数求和，在第三批重放。

每批示例提供两张源表和独立填写的目标；1–4批示例中的两张表名称保持一致，列顺序可以变化。点击搜索后检查连接类型、键和候选，再明确选用。任务保存为现有 DataJob JSON，可在多表任务工作台载入和重放。不同程序可能符合所有示例，候选排名不代表正确概率；新数据要核对。

CLI格式：`learn-join --pairs pairs.json --out report.json`；`job --report report.json --choose 0 --out job.json`；`run-job --job job.json --sources next.json --out result.csv`。每个 `pairs.json` 条目为 `{"sources":[{"name":"orders","file":"orders.csv"},{"name":"catalog","file":"catalog.csv"}],"target":"output.csv"}`；所有文件路径相对 `pairs.json`。命令以 `node bin/exampleloom.mjs` 开头。完整可运行 CLI 和源文件由 `node scripts/join-learning-test.mjs` 生成与验证。

## 搜索范围与边界

- 每批恰好两个命名表；一或两个字符串相等键；inner、left、full、semi、anti 五种连接；尝试两个源表方向。右键重复时只有实际输入出现并可以重放，才退到显式 many-to-many 关系。默认空字符串键不匹配。
- 连接之后尝试至多一个选列、汇总或排序操作；每个连接假设最多保留一种可行的后续程序。连接标记、列冲突和其他语义与 [v0.13](V013.md) 的显式操作相同。搜索不会自动推断任意正则、连接后的任意多步程序或任意 DataJob。
- 每源至多64行、8列，目标至多256行、16列；每个训练单元格至多1024 UTF-16单位，所有示例数据值合计至多100000单位。默认最多1024次连接假设、8个候选，最多4096次；学习阶段在生成连接结果前限制512行、8192单元格和250000文本单位。`truncated`包含搜索预算、候选上限或中间结果限额；触及限额不能解释为一定无解。
- 所有输出候选在返回前对**全部训练批次原始源表**重放。多批次的源表列按名称对齐，目标表的列名、行序和全部单元格均需一致。候选家族多样性只是保留策略，不保证覆盖所有可能程序。
- API `synthesize_join_jobs(examples, options?)`；JSON 操作同名，`examples` 为 `[{"sources":[{"name":"a","table":...},{"name":"b","table":...}],"output":...}]`。只接收训练输入及目标，不接收测试答案；返回每个候选的 `job`、搜索数和截断状态。

## 与同类研究的关系

[PROSE](https://www.microsoft.com/en-us/research/project/prose-framework/) 提供从示例合成受DSL约束程序的框架；[Foofah](https://github.com/umich-dbgroup/foofah)提供示例驱动的数据转换合成；[PATSQL](https://github.com/NAIST-SE/PATSQL)提供由示例推导 SQL。这里参考其问题定义，独立实现有限 MoonBit 候选搜索和原 DataJob 重放；没有移植三者代码，也没有宣称覆盖其完整语言、SQL或算法创新。三者在输入、DSL及运行环境上存在差异；若未在相同任务和环境实际运行，不给出跨工具性能结论。

原 Foofah 单表任务口径保持不变，v0.14 本机复测首候选仍为198/225；多表构造案例的测试结果不能加到该分子或分母。多表结果与真实用户采用、盲测及比赛审核均为不同问题。
