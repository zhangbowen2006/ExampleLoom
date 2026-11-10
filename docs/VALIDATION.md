# v0.5 验证记录

本地使用 Windows、MoonBit 编译器 `0.10.17+093cb8f9c`、moon `0.1.20261021` 和 Node v24.22.1。两个工作台和 CLI 使用同一份编译后的 MoonBit 引擎。[当前版本 CI](https://github.com/zhangbowen2006/ExampleLoom/actions) · [功能对比与场景](CAPABILITIES.md)

| 复现命令 | 实测范围 |
| --- | --- |
| `moon fmt --check`、`moon check --deny-warn --target all`、`moon info` | 格式、所有后端的静态检查、公开包接口 |
| `moon test --deny-warn --target js`，再分别指定 `wasm-gc` 与 `wasm` | 三个本地后端各 87 项通过。Linux native 由同一版本的 CI 执行 |
| `node scripts/integration.mjs` | 原有逐行工作流、CLI、配方按列名重绑定、CSV 往返及批量处理 |
| `node scripts/advanced-test.mjs` | 三个逐行、八个结构场景在新输入上逐格核对。使用 JavaScript 共同正则语法对照捕获 200 项，加上整串、局部匹配和全局替换 330 项 |
| `python scripts/verify-grouping.py` | 从两个训练批次经 CLI 学习，保存第一候选，换用其余 282 个真实时区，输出 236 个地区、388 条地区时区关系，SQLite 对照值与顺序全部通过 |
| `node scripts/public-data-test.mjs` 和 `python scripts/verify-sqlite.py` | 另有三个公开目录及 SQLite 实际导入、查询 |
| `python scripts/generate-oracle-cases.py` 和 `node scripts/oracle-test.mjs` | pandas 3.1.0 生成独立期望值。36 组构造任务、72 次显式执行，36 组在新表上首候选通过 |
| `node scripts/browser-test.mjs` 和 `node scripts/advanced-browser-test.mjs` | 真实浏览器完成选例、学习、选用、留出预览和 CSV 下载。覆盖多训练批次、正则提示、修改后旧结果失效、8 对上限及窄屏 |

浏览器验证先执行 `node scripts/build.mjs`、`node scripts/advanced-test.mjs`，再运行 `node scripts/serve.mjs`。CI 安装 Playwright，上传逐项证据与失败日志。本文的 530 项正则对照只覆盖两个实现的共同语法。

逐题成功、泛化、耗时、超时及排除原因见[外部基准](BENCHMARKS.md)。上版记录见 [v0.4 验证](https://github.com/zhangbowen2006/ExampleLoom/blob/v0.4.0/docs/VALIDATION.md)。
