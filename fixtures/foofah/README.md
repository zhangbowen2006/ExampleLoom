# Foofah 上游独立任务

来源：[umich-dbgroup/foofah](https://github.com/umich-dbgroup/foofah/tree/970864cd53b4c774a3dbdf4589d207f57ec63208/tests/data)，固定提交 `970864cd53b4c774a3dbdf4589d207f57ec63208`。

完整收录此版本 `tests/data/exp0_*.txt` 的 **250 个任务**，没有按我们的成功与否挑选。每个文件包含上游的 InputTable、OutputTable、TestingTable、TestAnswer；原样保留。MIT、Copyright (c) 2017 University of Michigan，完整许可为 [LICENSE.md](LICENSE.md)。这是主仓库许可范围内的数据；没有从许可证尚未确认的独立 foofah_benchmarks 仓库复制内容。

`manifest.json` 记录下载地址、固定源码提交、归档 SHA-256 和每个文件 SHA-256。`python scripts/import-foofah.py` 在现有数据上离线核验；缺文件或哈希不匹配时失败，不静默重新下载覆盖。首次导入只复制选定数据与许可证，不执行上游代码。

基准方法与失败计数见 [BENCHMARKS.md](../../docs/BENCHMARKS.md)。这些任务参与本次实现改进，不能称为从未看过的盲测。上游测试表是单独传入的评估数据；脚本禁止将 TestAnswer 传给学习器或用于选首候选。上游不同任务/样例数量有相关性，部分测试行会与训练行重复，因此同时报告任务族和输入行重叠。


v0.4 审计发现 25 个 TestAnswer 为 `[["NOT AVAILABLE, SORRY"]]`，涉及任务族 3、18、24、28、41。它们保留在全部 250 任务的清单与训练一致性统计中；仅 225 份有实际测试答案的任务用于测试成功率。v0.3 的 105 个成功数未变，但将全部 250 份称为可评估测试任务不准确，已在当前报告纠正。
