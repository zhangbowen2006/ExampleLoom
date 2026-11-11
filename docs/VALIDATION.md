# v0.7.0 验证记录

本地使用 Windows、MoonBit 编译器 `0.10.17+093cb8f9c`、moon `0.1.20261021` 和 Node v24.22.1。两个工作台和 CLI 使用同一份编译后的 MoonBit 引擎。[当前版本 CI](https://github.com/zhangbowen2006/ExampleLoom/actions) · [功能对比与场景](CAPABILITIES.md)

| 复现命令 | 实测范围 |
| --- | --- |
| `moon fmt --check`、`moon check --deny-warn --target all`、`moon info` | 格式、所有后端的静态检查、公开包接口 |
| `moon test --deny-warn --target js`，再分别指定 `wasm-gc` 与 `wasm` | 三个本地后端各 122 项通过。Linux native 由同一版本的 CI 执行 |
| `node scripts/integration.mjs` | 原有逐行工作流、CLI、配方按列名重绑定、CSV 往返及批量处理 |
| `node scripts/advanced-test.mjs` | 五个逐行、九个结构场景在新输入上逐格核对。使用 JavaScript 共同正则语法对照捕获 200 项，加上整串、局部匹配和全局替换 330 项 |
| `python scripts/verify-grouping.py` | 从两个训练批次经 CLI 学习，保存第一候选，换用其余 282 个真实时区，输出 236 个地区、388 条地区时区关系，SQLite 对照值与顺序全部通过 |
| `node scripts/public-data-test.mjs` 和 `python scripts/verify-sqlite.py` | 另有三个公开目录及 SQLite 实际导入、查询 |
| `python scripts/generate-oracle-cases.py` 和 `node scripts/oracle-test.mjs` | pandas 3.1.0 生成独立期望值。36 组构造任务、72 次显式执行，36 组在新表上首候选通过 |
| `node scripts/browser-test.mjs` 和 `node scripts/advanced-browser-test.mjs` | 真实浏览器完成选例、学习、选用、留出预览和 CSV 下载。覆盖多训练批次、正则提示、修改后旧结果失效、8 对上限及窄屏 |
| `node scripts/browser-recovery-test.mjs` | 延迟真实 Worker 请求，验证保存和载入期间修改训练表会使旧操作失效，取消重新搜索后旧候选清空，模拟 Worker 错误后，新 Worker 能成功执行管道。忙碌时文件选择被禁用，完成后恢复 |
| `node scripts/table-comparison-test.mjs` | 无目标的新批次比较、显式补样、第三批序列化重放、错误分组，以及两道保持原样的 Foofah 任务。正确答案只用于事后核验，不用于比较或选择 |
| `node scripts/table-comparison-browser-test.mjs` | 真实 Worker 比较、目标留空的补样、再学习与下载、全部失败状态、可见比较面板的 390px 布局，以及修改后延迟结果失效 |
| `python scripts/generate-sort-oracle.py`、`node scripts/sorting-test.mjs` | 128 组 Python Decimal/稳定排序参考；商品目录、多字段发票、宽表展开再排序三个完整学习与新批次流程。保留数值原文、前导零、负数、等值稳定性 |
| `node scripts/sorting-browser-test.mjs` | 三个排序场景的真实 Worker 学习与 CSV 下载、管道保存/载入、非法数值报出行列并禁止旧结果导出 |

浏览器验证先执行 `node scripts/build.mjs`、`node scripts/advanced-test.mjs`，再运行 `node scripts/serve.mjs`。CI 安装 Playwright，上传逐项证据与失败日志。本文的 530 项正则对照只覆盖两个实现的共同语法。

逐题成功、泛化、耗时、超时及排除原因见[外部基准](BENCHMARKS.md)。上版记录见 [v0.5.1 验证](https://github.com/zhangbowen2006/ExampleLoom/blob/v0.5.1/docs/VALIDATION.md)。

本轮对完整 250 道 Foofah、104 道可评估字符串任务再次运行。任务清单、训练样例和预算保持 v0.6.0 口径，逐题训练/首候选/候选上界判定均未变化。表格仍为 179/225，字符串协议 2（训练上限 32）为 104/104；仍保留表格 46 道失败、缺答案与矛盾原题的说明。一次重放的耗时不用于宣称性能提高。[本轮记录](evidence/maintenance-v0.6.1.json) · [交互消歧记录](evidence/table-comparison-v0.6.1.json)

新增测试覆盖指定分隔词的替换、字面美元转义、可选后缀的重复应用、完整字段预算与无关条件分支、跨训练表打包投影、单记录拆分转长表、单行训练的提取和键值记录的批次变化。公开接口和 JSON 协议共同使用默认分隔符，浏览器通过 `=` 记录的实际工作流验证该路径。
