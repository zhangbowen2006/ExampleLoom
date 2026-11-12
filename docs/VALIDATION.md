# 当前验证：v0.13 系列

v0.13.1只修正文档，执行核心与v0.13.0相同。已核验的v0.13.0 [CI](https://github.com/zhangbowen2006/ExampleLoom/actions/runs/43241617005)在JS、Wasm GC、Wasm、native各175项测试全部通过；最新文档修订的CI以[运行记录](https://github.com/zhangbowen2006/ExampleLoom/actions)为准。全新Mooncakes消费项目在三个后端各29项测试通过。

当前另外有500组独立连接、250组合表、350组高精度Decimal构造参考、88852项PCRE2共享语法构造对照，以及三个多源任务的API/CLI/真实Worker保存重载、取消重试和错误处理。构造测试不等于客户采用、完整PCRE兼容或外部任务全对。完整Foofah仍198/225，候选上界211/225。

- [五轮实现、修正和边界](V013.md)
- [连接/合表证据](evidence/v0130-multisource.json)、[精确小数证据](evidence/v0130-decimal.json)
- [多源任务与真实浏览器](evidence/v0130-jobs.json)、[浏览器逐项记录](evidence/v0130-job-browser.json)
- [外部任务逐题结果](evidence/v0130-benchmark.json)

以下保留历史版本记录，其中“本轮”“当前”仅指相应历史版本，不是本页的最新统计。

## v0.11.0 历史验证记录

五轮本地JS、Wasm GC、Wasm测试数依次为148、149、150、152、153；各轮全部通过。最终完整Foofah198/225；高级浏览器28项，包含默认推导、明确意图选择、补空拆列及显式重复字段JSON列表。列表另有250组固定种子构造参考与真实CLI。PCRE2 88,852项仍通过。远程Linux native及持续集成以各提交的[CI](https://github.com/zhangbowen2006/ExampleLoom/actions)实际状态为准。[五轮记录](FIVE_ROUNDS.md)

## v0.10.0 历史验证

Windows 本地 JS、Wasm GC、Wasm 各运行 147 项 MoonBit 测试全部通过；完整 PCRE2 10.47 构造对照共 88,852 项，另有 24,624 项 JavaScript 共同语法对照、500 个正则边界构造、250 组记录构造和 5 个非法数据拒绝用例。浏览器实际执行新增学习示例，以及额外输入列管道的保存、载入和重放。[正则记录](evidence/pcre2-v0.10.0.json) · [记录转换](evidence/record-pivot-v0.10.0.json) · [浏览器记录](evidence/advanced-browser-v0.10.0.json)。这些不是生产采用证明，也不构成完整 PCRE 一致性证明。Linux native 结果以[对应提交的 CI](https://github.com/zhangbowen2006/ExampleLoom/actions)为准。

## v0.9.1 历史验证

v0.9.1 只更新版本号和 CI 浏览器依赖选择。v0.9.0 的一次运行中，Ubuntu 软件源 DNS 解析失败导致依赖安装长时间停滞；现在优先使用 GitHub Ubuntu 运行器预装 Chrome，缺少时才限时安装。该补丁的应用引擎与 v0.9.0 的可执行引擎哈希相同，以下功能基准沿用 v0.9.0 的逐题证据。实际 CI 状态以本次运行结果为准。

v0.9 的 JS、Wasm GC、Wasm 本地后端各通过 140 项 MoonBit 测试，含 5 项来自上游的 Unicode 测试；以相同口径重放完整 Foofah 与 SyGuS。PCRE2 10.47 的构造对照包含 525 个模式/文本组合及 2,938 对上游 Unicode 简单折叠映射，共 7,663 项匹配、捕获、替换和反向引用对照；原有 JS 共同语法构造对照为 24,624 项。新增三组可学习的变长记录、分组报表和分行明细流程，在真实浏览器和 CLI 中运行；高级浏览器检查共 20 项。[结果与限制](BENCHMARKS.md) · [PCRE2 记录](evidence/pcre2-v0.9.0.json) · [浏览器记录](evidence/advanced-browser-v0.9.0.json)。本机没有 MSVC，Linux 原生后端以本次 GitHub CI 实际结果为准。

以下 v0.8 验证记录和数字保留作为历史资料。

## v0.8 验证

本轮三个本地后端各 131 项通过，含 5 项随 Apache-2.0 源码保留的上游 Unicode 测试；`moon check --deny-warn --target all` 通过。本机未安装 MSVC，原生测试不能在本机执行；Linux native 仍由公开 CI 实际执行，是否成功以对应运行状态为准。

`node scripts/regex-extended-test.mjs` 通过 23,940 项共同语法构造差分与三个完整流程，`node scripts/regex-robustness-test.mjs` 对 500 个固定种子的构造模式验证边界（83 接受、417 拒绝、无宿主崩溃）。真实浏览器新增断言提示学习与扩展正则四步表格组合；高级浏览器检查总数 17。[正则证据](evidence/regex-v0.8.0.json) · [边界证据](evidence/regex-robustness-v0.8.0.json) · [浏览器记录](evidence/advanced-browser-v0.8.0.json) · [详细范围](REGEX_PROFILE.md)

原有逐行/CLI、530 项正则共同语法对照、结构学习、补样比较、128 组独立排序参考、36 组 pandas 参考、公开数据/SQLite、浏览器恢复和排序检查均重跑通过。完整外部任务保持原评分、训练和预算，具体成绩及未解决任务见[本轮重放](evidence/maintenance-v0.8.0.json)。以下表格保留 v0.7 的验证项，122 是当时测试数，不是当前总数。

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
