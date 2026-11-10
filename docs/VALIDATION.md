# v0.4 实际验证记录

日期：2026-11-10（Asia/Shanghai）。工程结果不代表赛事通过。

本地 Windows / moon 0.1.20261021、moonc 0.10.17+093cb8f9c / Node 24.22.1。

| 实际命令 | 结果 |
| --- | --- |
| moon fmt --check、moon check --deny-warn --target all、moon info | 通过，公开接口已更新 |
| moon test --deny-warn --target js / wasm-gc / wasm | 三个本地后端各 78 项通过 |
| node scripts/integration.mjs | 原有场景、CLI、配方重绑定、150 个 CSV 往返及万行处理通过 |
| node scripts/advanced-test.mjs | 条件与正则、6 个结构场景、新批次表和结构 CLI 通过；200 个正则捕获与 JS 共同语法对照一致 |
| node scripts/public-data-test.mjs、python scripts/verify-sqlite.py | 公开目录 1,390 行及 4,141 个留出字段值通过，SQLite 接收和查询通过 |
| python scripts/generate-oracle-cases.py、node scripts/oracle-test.mjs | pandas 3.1.0 参考：72 次执行一致，36 个构造任务学习后在新表通过 |
| node scripts/advanced-browser-test.mjs、node scripts/browser-test.mjs | 真实 Edge 中新旧工作台、8 个新增/扩展流程、CSV 下载、错误和过期结果禁止导出、390px 无横向溢出通过 |
| node scripts/compare-benchmarks.mjs | 旧新各三轮、全部 250 任务，结果稳定；完整成功/失败与速度取舍见 BENCHMARKS |

本地缺少 C 编译器，未声称 Windows native 已跑。Linux Native 由当前提交的 [CI](https://github.com/zhangbowen2006/ExampleLoom/actions) 运行，需按对应提交查看，历史成功不替代当前版本。

新测试验证动态标签及空标签、重复透视拒绝、列合并顺序与不修改输入、变长记录和非法前缀、上下文替换及孤立明细错误、重复源列的独立别名、排名泛化、填充再透视、多训练对的维度消歧、无提示的正则上下文和有限替换学习。解释器可执行的范围仍大于学习器。

外部任务来自固定上游 MIT 数据，不是自编业务演示；它们参与过开发，不能称为盲测。25 份测试答案占位已单列，有答案任务为 225 个，且测试数据只在学习后使用。当前有 6 个旧版通过而新版回退的任务，详见完整比较。pandas 构造验证不与外部任务混算。

原始证据、下载 CSV、浏览器截图及本地/CI 产物在 artifacts，公开的精简固定快照在 docs/evidence。该项目没有真实客户采用或一般生产准确率证据；不保证初审、验收或获奖。
