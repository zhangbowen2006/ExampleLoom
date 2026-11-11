# 初审核验事实（2026-11-11，v0.6.1）

这是项目事实与复现指引，不是正式申报书，也不代表组委会审核结论。项目名称、用途、现有接口、操作集合和搜索预算沿用 ExampleLoom；本轮补齐表格候选比较与显式补样。

## 当前官方口径

2026-11-11 实际加载的[十一月官网](https://moonbitlang.github.io/Hackathon2026/)明确要求 MoonBit 为主、公开且可追踪的仓库、README/示例/测试、实质新增工作、清晰许可与参考来源，以及参赛者能够解释 AI 辅助的实现。页面未给出具体截止日期，要求以官方通知为准。

展开[当前报名表](https://bxup9uklfcb.feishu.cn/share/base/form/shrcnWUMlgpbwHaXgzV7HmNhNhg)的新项目季度选项后，可见一页以内 Markdown、至少三个完整场景、至少十个有效提交，以及不要使用 AI 编写申报书的要求。表单仍写三次提交、可重复修改。剩余名额和本人报名记录无法从公开页面确认。

## 仓库可核验的交付

| 要求或关注点 | 证据与核验方式 |
| --- | --- |
| MoonBit 实现核心 | 搜索、行表达式、结构运算、比较和协议均在根目录 MoonBit 源文件。`moon check --deny-warn --target all`；公开接口见 [pkg.generated.mbti](../pkg.generated.mbti) |
| 可追踪与独立运行 | [公开仓库](https://github.com/zhangbowen2006/ExampleLoom)、[提交记录](https://github.com/zhangbowen2006/ExampleLoom/commits/main/)、[README](../README.md)。浏览器本地 Worker 和 CLI 调用同一核心，不调用 PROSE、Foofah 或云模型 |
| 条件与正则 | 条件分支、捕获、匹配、全局替换和捕获组重排已有可运行流程；530 项共同方言对照。支持边界详见 [CAPABILITIES](CAPABILITIES.md)，不宣称 PCRE 全覆盖或自动推断任意正则 |
| 表格转换及新批次 | 既有 22 类操作、1–8 对训练表、宽长表和记录重组、分组计数及有符号整数聚合。[三个完整场景](CAPABILITIES.md#可以复现的三个完整场景)包含输入、使用者、目标和验证 |
| 本轮实质工作 | MoonBit 比较完整输出与执行错误，定位差异；工作台只复制输入，目标由使用者提供，重新学习再用于第三批。没有改动搜索算子、预算、成本排序或 v1/v2 序列化格式 |
| 测试及 CI | 108 项核心测试；[CI](https://github.com/zhangbowen2006/ExampleLoom/actions)覆盖四后端、完整工作流、公开数据/SQLite、pandas 和真实浏览器。细节与局限见 [VALIDATION](VALIDATION.md) |
| 开源与来源 | 根目录 [MIT LICENSE](../LICENSE)、[来源/许可证](RESEARCH.md)、数据目录中的上游许可和哈希。PROSE/OpenRefine 仅作方法参考，Foofah 数据按原许可使用 |
| 可分发 | Mooncakes 命名空间 `zhangbowen2006/exampleloom`；[版本包](https://github.com/zhangbowen2006/ExampleLoom/releases)附源码、工作台、摘要与发布核验记录。安装后需以实际依赖版本运行测试 |

## 五分钟交互复现

```sh
moon check --deny-warn
moon test --deny-warn
node scripts/build.mjs
node scripts/table-comparison-test.mjs
node scripts/serve.mjs
```

打开 `/structure.html`，选择「候选歧义与补样」，搜索后比较下一批结果；初始八个候选产生四种预测。点击补样会留下空目标，按示例的 `refinement_target` 填写正确输出后再搜索。随后将 `after_refinement.input` 用作新批次，明确选用管道并预览，逐格核对第三批期望表。[完整场景文件](../examples/structures/ambiguous-records.json)

其他独立流程可分别使用供应商编码、上下文 ref 捕获、宽表转长表、地区订单汇总及键值记录网格示例，不需要参考系统的安装环境。

## 仍然保留的审核风险

- 外部表格首候选为 179/225，仍有 46 道失败；字符串协议 2 是训练上限 32 的 104/104，并不是原六条训练口径。基准已用于开发、原 SyGuS 语法未强制执行，不能宣传为盲测或通用正确性保证。[基准定义](BENCHMARKS.md) · [本轮无回退重放](evidence/maintenance-v0.6.1.json)
- 候选分歧可指出需要更多信息的地方；候选一致也可能共同出错。用户提供的正确目标才是新增监督信号。比较和“至少一个候选正确”的事后指标都不能代替自动首候选成功率。
- 缺少客户部署和采用证据。现有场景与参考实现验证说明可运行性，不构成业务收益或生产部署证明。
- 申报书应按真实范围描述有限、可检查、可重放的转换程序学习。是否达到初审要求、十一月具体截止日期、个人名额及旧报名的计数方式仍由组委会确认。本人需独立准备正式申报、填写私密信息并提交；仓库推送与包发布不代表报名成功。
