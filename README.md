# ExampleLoom

**给出几个样例，生成可检查、可重用的数据转换程序。**

[在线工作台](https://zhangbowen2006.github.io/ExampleLoom/) · [Mooncakes 0.1.0](https://mooncakes.io/docs/zhangbowen2006/exampleloom) · [CI 与运行证据](https://github.com/zhangbowen2006/ExampleLoom/actions) · [版本下载](https://github.com/zhangbowen2006/ExampleLoom/releases)

ExampleLoom 是使用 MoonBit 实现的程序合成引擎、独立浏览器工作台和 CLI。它面向反复整理编号、名单、文件目录的人：导入 CSV/JSONL，标注输入输出样例，比较候选程序的不同解释，明确选择后保存配方并用于下一批数据。不依赖 Excel、云模型、PROSE 或维护者的其他项目。

![工作台运行截图](docs/assets/workbench.png)

## 快速体验

要求 MoonBit（验证版本 `moonc 0.10.17+093cb8f9c`、`moon 0.1.20261021`），工作台/CLI 另需 Node.js ≥20。没有 npm 运行时依赖。

```sh
moon check --deny-warn
moon test --deny-warn
moon run cmd/demo
node scripts/build.mjs
node scripts/serve.mjs
```

打开 <http://127.0.0.1:4173>，点击“供应商编码”“活动名单”或“素材目录”。两个样例已填好；点击生成候选，检查分歧，选用规则，再预览整批结果。切换示例输出字段可继续添加另一条规则。

点击“看看歧义”可重现：`订单-0012 → 0012`、`订单-0081 → 0081` 同时支持“末尾四位”和“最后一个连字符后的完整编号”。`订单-123456` 能区分它们。补充该行正确输出再搜索。此交互是已有 PBE 技术的应用，不是算法首创声明。

## 已实现功能

- MoonBit 原生有限表达式解释器、输出引导的程序搜索、稳定候选排名。
- 多输入列、多个独立输出字段；字段、常量、分隔词、ASCII 连续段、Unicode 字符区间、trim、ASCII 大小写、拼接、五种显式公历日期格式。
- 实际输入行上的候选分歧（包含失败预测），提示补充有区分力的样例。
- 版本化 JSON 配方；按列名绑定新数据，列顺序变化不影响已保存规则。
- 严格 CSV/JSONL 导入；保留前导零；批处理按行报告错误；失败时停止 CSV 导出。
- 独立中文工作台：文件导入、样例编辑、多字段配方、预览、下载、Worker 取消、手机布局。运行期间无外部数据请求。
- CLI 和公开 Mooncakes 库接口。实际验证与限制见 [VALIDATION.md](docs/VALIDATION.md)。

## 三个完整使用场景

| 使用者与问题 | 输入与操作 | 输出与验证 |
| --- | --- | --- |
| 小商家/运营整理供应商复合编码 | `examples/products/input.csv`；提供两个型号/颜色样例，分别选择规则 | 型号 `0012`、`123456` 等保留前导零，颜色转大写；另外两行不参与训练，逐值检查 |
| 活动组织者生成名单标签 | `examples/labels/input.csv`；用姓名、班级示范 `A1 / 陈雨`，另外复制编号字段 | 新行生成 `C20 / 赵晨`，编号不变；测试重排列后重用配方仍一致 |
| 内容创作者整理音视频文件 | `examples/media/input.csv`；标注两个日期和 take 编号 | 未见的 `20240229` 正确变为 `2024-02-29`；`invalid.csv` 中 `20260229` 报错并停止 CSV 导出 |

这些是构造的演示数据，并非已获客户采用的证明。可复现实验：

```sh
node scripts/integration.mjs
```

它验证三个场景与额外歧义演示、留出行、配方往返、列名重绑定、CLI 全流程、150 组 CSV 往返，以及 10000 行批处理，并写入 `artifacts/integration-results.json`。

## CLI

```sh
node bin/exampleloom.mjs learn --data examples/products/input.csv --examples examples/products/model-labels.json --out candidates.json
node bin/exampleloom.mjs recipe --report candidates.json --choose 0 --name model --out product.recipe.json
node bin/exampleloom.mjs apply --data examples/products/input.csv --recipe product.recipe.json --out product.result.csv
```

候选编号从 0 开始，选择需要显式 `--choose`。检查报告中的其他候选与分歧后再选择；排名不表示正确率。标签文件为 `[{"row":0,"output":"0012"}, ...]`，行号不计表头。JSONL 可加 `--format jsonl`。`run request.json` 支持完整 [JSON 协议](docs/PROTOCOL.md)。

## MoonBit 库

安装发布模块后在 `moon.pkg` 中导入 `"zhangbowen2006/exampleloom" @loom`。完整可运行调用见 `cmd/demo/main.mbt`。

```moonbit
let report = @loom.synthesize([
  { input: ["订单-0012"], output: "0012" },
  { input: ["订单-123456"], output: "123456" },
])
// 先检查 report.truncated、候选表达式和 disagreements，再选择。
let output = @loom.evaluate(report.candidates[0].expression, ["订单-00987"])
```

API 通过 `LoomError` 报告普通输入错误；调用者需要处理异常和空候选数组。`attempt` 返回值形式的错误。`pkg.generated.mbti` 是生成的公开接口。

## 边界与可靠性

**这是有界的字符串程序合成器。**不支持任意自然语言任务、表格连接/重排、条件分支、循环、完整正则上下文或所有 Unicode 大小写规则。训练样例一致不保证未见数据正确；`truncated=true` 表示候选不完整。观察到的搜索语法依赖首个样例。

默认最多 32 个样例、16 输入列、每个样例字段 128 字符、64 候选、6 个拼接片段。整表最多 20000 行、64 列；歧义检查最多前 5000 行。ASCII 词类与大小写有明确限制；日期必须指定格式，不能猜月日。全部预算、状态含义及算法见 [ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 工程验证

```sh
moon fmt --check
moon check --deny-warn --target all
moon test --deny-warn --target wasm-gc
moon test --deny-warn --target js
moon test --deny-warn --target wasm
moon info
```

原生后端另需 C 编译器；Windows 需要 MSVC C++ 工具与 SDK。CI 在 Linux 同时测试 native。可选浏览器回归：安装 Playwright 1.62.1 和 Chromium，启动本地服务后运行 `node scripts/browser-test.mjs`；它生成桌面/手机截图和 JSON 证据。也支持通过 `PLAYWRIGHT_MODULE` / `BROWSER_EXECUTABLE` 指定已安装环境。

## 来源与维护

MIT 开源。仅依赖工具链 `moonbitlang/core`（Apache-2.0）；浏览器回归使用 Playwright（Apache-2.0，开发期依赖）。交付的静态 JS 包含编译的 core 代码，分发其许可证与版权声明。

该项目由维护者在 AI 辅助下从新目录实现，没有复制旧项目业务代码。算法思想参考既有 PBE 研究；明确对比 Flash Fill、PROSE、Foofah、MoonFrame 和 moon-databridge，见 [调研与来源](docs/RESEARCH.md)。不声称全球唯一，也不保证通过竞赛审核或获奖。

后续优先扩大独立验证数据与真实使用反馈、减少搜索截断、提升候选多样性。欢迎附上最小输入/输出样例、期望结果、工具链版本和复现步骤提交 issue；请移除私人数据。
