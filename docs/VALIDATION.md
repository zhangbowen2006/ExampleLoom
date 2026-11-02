# 实际验证记录

本记录是工程证据，不是赛事验收结论。日期：2026-11-02（Asia/Shanghai）。公开远程 CI 与发布状态在完成后另行更新，不以配置存在代替通过结果。

## 本地环境与命令

Windows，`moon 0.1.20261021 (a4f8933)`、`moonc v0.10.17+093cb8f9c`、Node.js v24.22.1。

| 命令/检查 | 实际结果 |
| --- | --- |
| `moon fmt --check` | 通过 |
| `moon check --deny-warn --target all` | 通过 |
| `moon test --deny-warn --target wasm-gc` | 41 / 41 |
| `moon test --deny-warn --target js` | 41 / 41 |
| `moon test --deny-warn --target wasm` | 41 / 41 |
| `moon info` | 生成并检查公开 `.mbti` 接口 |
| `moon run cmd/demo` | 三个 MoonBit 调用示例运行成功，留出输出分别为 `123456`、`C20 / 赵晨`、`2024-02-29` |
| `node scripts/build.mjs` | 编译 MoonBit 为 JS 并生成独立静态工作台 |
| `node scripts/integration.mjs` | 场景、CLI、CSV 往返、10000 行批处理均通过 |
| `node scripts/browser-test.mjs` | 桌面/手机布局、多字段操作、歧义补充样例、下载、无效日期阻止导出均通过；无页面脚本异常、无外部数据请求 |

`moon test --target all` 曾在 Windows 原生后端构建计划阶段因缺少 MSVC C++ 工具/Windows SDK 失败；不是原生执行通过的证据。Linux CI 配置另行运行 native，结果以实际 Actions 为准。

## 测试内容

41 项 MoonBit 测试覆盖：Unicode scalar 截取、边界错误、连续/负索引分隔词、ASCII 大小写、多列拼接、1900/2000 闰年、日期往返、严格 CSV 引号/BOM/换行/空字段、JSONL 模式、矛盾样例、预算耗尽、不同程序保留、空输出、原始行分歧、配方导入和重绑定、失败行位置、节点和批量输出限制。

端到端场景包含产品、名单、素材三项和歧义演示，共 7 个输出字段任务。每个任务两行训练、两行留出。脚本同时验证列顺序改变后结果一致、配方序列化往返、150 组构造 CSV 值往返以及完整 CLI 链路。测试数据为构造数据，规模有限，不代表真实生产准确率。

## 一次实际性能观测

2026-11-02 本地 release JS 一次运行：各场景学习约 2–17 ms；10000 行字符串提取、JSON 输出与 CSV 生成合计约 41 ms。此值是单机单次样本，包含 JSON 协议开销，无竞品对照，不作为性能领先声明。重新运行会因机器和热身不同而变化。

部分场景触及 64 个候选上限；素材日期搜索触及 200000 步上限但已找到 4 个候选。状态真实返回 `candidate_limit` / `step_limit` 和 `truncated:true`；不能写成已经找到完整程序集。未截断也只表示本次观察语法范围内搜索结束。

## 可复现证据

集成测试写入 `artifacts/integration-results.json`；浏览器测试写入 `artifacts/browser-results.json`、桌面和手机截图；CLI 产物也在 artifacts 中。该目录不提交到 Git，CI 通过 Actions artifact 提供当次证据。示例源数据和测试脚本均已纳入版本控制。

维护者下一步应使用经过授权且去除个人信息的独立数据、明确的目标任务和留出样本，报告规则成功/失败及人工补充样例次数。当前没有真实客户采用、广泛成功率、获奖或报名通过证据。
