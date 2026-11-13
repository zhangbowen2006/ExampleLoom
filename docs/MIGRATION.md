# v0.15.0 迁移说明

旧行配方v1、表格管道v2编码继续可读，默认自动学习仍为`infer`。新增操作需新引擎执行；旧引擎会拒绝未知操作。

原生API的公开`TableStep`枚举增加`FlattenRows`、`SplitColumnPadded`、`PivotRecordLists`。下游若穷举匹配该枚举，需要增加分支或适当的通配分支；这属于源码兼容性变化，因此使用次版本号升级。JSON兼容不等于所有原生源码无须修改。

`synthesize_table`增加可选`intent`参数；旧调用方式保留。JSON请求新增`intent`，并拒绝未知字段，以便尽早暴露拼写错误。`flatten_all`只检查明确的整批展平，不执行通用搜索。

旧`split_column`与`pivot_records`的严格错误行为保留。可选字段需明确使用`split_column_padded`；重复值列表需明确使用`pivot_record_lists`。JSON数组字符串中，缺失为`[]`，真实空字符串为`[""]`；两者不会混合。

## v0.12 新增

公开 TableStep 增加 NormalizeLayouts；原生穷举匹配需新增分支。LayoutRule、synthesize_table_with_layouts 与 propose_table_input 为新公开接口。旧管道格式可继续读取；新规范化操作只能位于首步，其 Pipeline.columns 为历史输入元数据，由显式规则按名称绑定实际源列。规则不自动学习，新增源列不隐式保留。详见 [v0.12协议与边界](V012.md#接口与边界)。

## v0.13 新增

GroupMetric 增加 SumDecimal/MinDecimal/MaxDecimal；下游穷举匹配需加分支。旧Int64指标和旧JSON配方继续支持。新增 JoinSpec、UnionSpec、DataJob及确认式执行API，均可独立使用，不要求现有用户迁移到多源任务。详细合同与限制见 [v0.13](V013.md)。

## v0.14 新增

新增 JoinExample、JoinSearchOptions、JoinSearchReport 与 synthesize_join_jobs；不改变已有DataJob、旧JSON和单表学习的默认行为。多表学习仅支持两个源、有限键与一步后续操作，不保证候选完备。[使用与预算](JOIN_LEARNING.md)。

## v0.15 新增

`JoinSearchReport`增加`filter_evaluations`字段；如果下游手工构造该结构，需要补上该字段。JSON响应也增加同名计数。`evaluations`仍是连接假设数。新增有限的“连接后筛选再汇总”学习，输出仍使用原DataJob v1和Pipeline v2中的既有算子，执行端格式兼容。旧版只包含连接、选列、汇总或排序的已保存任务继续可用；新学习器可能返回更多训练一致的规则，不能假定候选编号跨版本保持一致。[范围与验证](V015.md)。
