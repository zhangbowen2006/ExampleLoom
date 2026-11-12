# 外部表格任务的转置实验（v0.14）

## 数据、方法和限制

选用 [Auto-Tables-Benchmark](https://github.com/LiPengCS/Auto-Tables-Benchmark) 固定版本 `45f91a7c9b7665690d2dfdce0c27fc777896bdab` 中 `ATBench/transpose` 的全部 28 道任务。下载压缩包的 SHA-256 为 `2ffac26151cbcb3396fc355b6522595a76bdfd1e1a2ac901491540f5f771ceb4`。输入与目标表格均取自上游；项目仓库不重新分发这批原始数据。[MIT 许可证](https://github.com/LiPengCS/Auto-Tables-Benchmark/blob/45f91a7c9b7665690d2dfdce0c27fc777896bdab/LICENSE)适用于上游仓库；使用者仍需自行确认各数据源条款。

每题将原始输入及完整目标表作为一对**训练样例**。在选定候选后，构造另一张行数和值均变化的输入表，以数学转置产生其期望输出，再逐格检查候选；这个探针由我们生成，并非上游提供的独立测试集。任务格式和早期运行结果在开发时已查看，因此不称为盲测。结果只反映此单一类别，不代表整个数据集或实际用户场景。全部 28 题均保留在分母；超出限制和执行失败计为失败。

## 本机结果

| 模式 | 训练拟合 | 改变行数后首候选正确 | 至少一个候选正确（事后上界） | 输入超限/错误 |
| --- | ---: | ---: | ---: | ---: |
| v0.13.1 自动搜索 | 17/28 | 0/28 | 17/28 | 11 |
| v0.14.0 自动搜索 | 17/28 | 0/28 | 17/28 | 11 |
| v0.14.0 使用者明确选择整表转置 | 23/28 | 23/28 | 23/28 | 5 |

自动搜索中，某些固定行数的打包程序与整表转置对训练样例同样成立；按当前成本排序，首候选在新行数上失败。用户指定 `transpose_all` 是**额外提供意图**，系统仅在该操作重放全部训练样例后返回，不能把辅助成绩称作自动推断成绩。该模式最多支持 64 行、64 列；5 个剩余任务超出当前表格列数限制，不能声称支持任意大表。

这里没有运行 Foofah、PROSE 或 Auto-Tables 可执行系统，也没有同机跨工具计时；这些数字不能用来比较不同工具的性能。候选存在不等于首候选正确，更不意味着能解决所有表格转换。此前 Foofah 题目的结果和本实验口径不同，不能合并计分。

## 复现

安装 Node.js 及 MoonBit，执行 `node scripts/build.mjs`，然后：

```sh
python scripts/import-autotables.py
node scripts/autotables-benchmark.mjs
```

Linux/macOS 显式意图复现：

```sh
TABLE_INTENT=transpose_all AUTO_BENCHMARK_RESULTS=artifacts/autotables/assisted.json node scripts/autotables-benchmark.mjs
```

PowerShell 显式意图复现：

```powershell
$env:TABLE_INTENT = 'transpose_all'
$env:AUTO_BENCHMARK_RESULTS = 'artifacts/autotables/assisted.json'
node scripts/autotables-benchmark.mjs
Remove-Item Env:TABLE_INTENT, Env:AUTO_BENCHMARK_RESULTS
```

脚本核对固定下载包的 SHA-256、保留每题来源和结果；完整运行的去原始数据记录：[v0.13.1 自动](evidence/autotables-v0131.json)、[v0.14.0 自动](evidence/autotables-v0140-auto.json)、[v0.14.0 显式意图](evidence/autotables-v0140-assisted.json)。固定参数为深度 4、状态 128、结构尝试 2000、候选 8、单题 5 秒。测试数据和结果保存在 `artifacts/autotables/`，不包含在公开工作台构建产物中。
