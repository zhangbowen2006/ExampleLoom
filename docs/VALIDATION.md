# 实际验证记录

日期：2026-11-10（Asia/Shanghai），v0.3.0。工程结果不等于赛事审核通过。

## 本地实际结果

Windows；moon 0.1.20261021、moonc 0.10.17+093cb8f9c、Node 24.22.1。

| 检查 | 结果 |
| --- | --- |
| moon fmt --check；moon check --deny-warn --target all | 通过 |
| moon test --deny-warn --target wasm-gc / js / wasm | 三个后端各 66 / 66 |
| moon info | 公开接口已生成 |
| node scripts/integration.mjs | 构造场景、歧义、CLI、配方往返/重绑定、150 组 CSV 往返、万行批处理通过 |
| python scripts/import-public-data.py | 6 份来源/许可证 SHA-256 校验，离线重建三组数据 |
| node scripts/public-data-test.mjs | 9 个字段任务，合计 4,141 个未用于该字段训练的值全部一致 |
| python scripts/verify-sqlite.py | Python CSV + SQLite 3.50.4 接收全部 1,390 行、4,170 个字段值，三个目录查询通过 |
| node scripts/browser-test.mjs | 构造/公开数据流程、两轮消歧、完整 CSV 下载、旧规则失效、多字段、手机布局通过；无脚本异常/外部请求 |

Windows native 缺 MSVC C++ / SDK，未在本机执行。远程 Linux native 结果以 [Actions](https://github.com/zhangbowen2006/ExampleLoom/actions) 对应提交为准；历史成功不代替当前提交检查。

66 项核心测试覆盖字符串/Unicode 边界、日期、严格解析、矛盾样例、预算、配方、批处理，并新增样例排列、重复样例、大小写与 trim、观察/显式分隔符、参数边界、转移缓存和 Token 后截取。

## 公开数据实验与真实失败

| 数据集 | 记录 | 初始标注 | 未参与最终训练的字段值 |
| --- | --- | --- | --- |
| IANA tzdb 2025b 时区 | 312 | 每字段 3 行，3 字段 | 927 / 927 |
| Unicode CLDR 48 locale | 766 | 每字段 3 行，3 字段 | 2,289 / 2,289 |
| github/gitignore 固定版本路径 | 312 | 每字段 3 行，模板名称另补 2 行 | 925 / 925 |

预期值由独立 Python 字符串运算生成，运行时选择首个候选，不用预期值挑选“碰巧正确”的其他候选。模板名称最初 3 条纯字母标注使首候选选择 ASCII 字母段，309 条留出中 **25 条错误**（如 C++、含数字名称）。按分歧排名依次补 C.gitignore → C 和 C++.gitignore → C++，最终规则为末级路径去 .gitignore 后缀，剩余 307 条一致。两条补充样例从最终留出计数排除。

本数据参与过实现改进，转换任务由项目指定，答案用于模拟人工补样例；不是独立盲测、客户试用或一般生产准确率。三个任务各含一个保留原标识的字段，不把复制字段包装为技术突破。版本、许可、全记录及生成方式见 [来源说明](../fixtures/public/README.md)。

与已发布 0.1.0 引擎使用相同任务和两次交互预算对照：旧版文件名与模板名称任务各仅 284 / 309 个值一致，两个任务失败；0.2.0 九个任务通过。基线取自旧版发布工作台，设置 ENGINE_PATH 指向提取的旧版 engine.mjs 后运行同一脚本。只比较自有版本，不宣称优于 PROSE、Foofah 或 Excel。

## 性能和搜索边界

v0.2 的一次历史本地 release JS 运行：构造场景学习约 2–21 ms，万行提取/JSON/CSV 合计约 46 ms；不冒充 v0.3 性能。仅单机单次观测，无跨工具性能结论。素材日期现在找到 64 个候选并触及候选上限；旧版曾触及步数上限。v0.2 使用转移缓存且改变步骤计数，不能把步数比写成加速倍数。

候选/原子/队列限制仍可能截断，状态如实返回；语法耗尽仅表示观察到的有限语法搜索结束。无分歧不保证正确。v0.3 已补条件、动态正则与表格结构；学习范围仍小于执行范围，不支持多表连接、数值聚合、任意谓词或全部 Unicode 大小写。没有真实客户采用证据。

## 复现与交付证据

CI 执行上述命令并在 Linux 测试 native；浏览器回归使用 Playwright 1.62.1。artifacts/integration-results.json、browser-results.json、public-data/results.json、sqlite-results.json 记录当次结果，Actions 提供下载。artifacts 不提交，私人申报文件不进入仓库/发布包。

公开仓库、工作台、Mooncakes 和 release 最终版本/提交以各服务实际显示为准。仅配置 CI 或准备上传不算发布成功。


## v0.3 新能力实际验证

本地 Windows，MoonBit/Node 版本同上。`moon fmt --check`、`moon check --deny-warn --target all` 通过；`moon test --deny-warn --target js/wasm-gc/wasm` 各 66 项通过。本地缺 C 编译器，因此不声称 Windows native 已运行，Linux native 以本版本 CI 结果为准。

`node scripts/advanced-test.mjs` 验证条件规则和正则捕获确实由学习器生成；三个结构场景在下一批表、列名重绑定和保存管道上逐值一致；真实 CLI 完成 learn-table → pipeline → transform。另有 200 个捕获结果与 JavaScript 的共同语法独立对照，包括 Unicode、空匹配、末次匹配和无匹配错误；这不是完整正则规格认证。

`node scripts/advanced-browser-test.mjs` 在真实 Edge 中完成上述五个流程和 CSV 下载，检查旧规则失效、不完整记录拒绝导出、390px 无横向溢出、无脚本异常及无外部数据请求；旧版浏览器/公开数据/SQLite 回归也重新通过。JSON 证据及截图在 `artifacts/`，CI 会上传这些结果。

外部 250 个 Foofah 任务的完整成功、泛化失败和超限记录见 [BENCHMARKS.md](BENCHMARKS.md)。它们是上游任务，但参与过此次开发，不称为盲测或生产成功率；没有运行 Foofah/PROSE 本体，不能对它们作数值排名。
