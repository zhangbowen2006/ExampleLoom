# v0.11.0 迁移说明

旧行配方v1、表格管道v2编码继续可读，默认自动学习仍为`infer`。新增操作需新引擎执行；旧引擎会拒绝未知操作。

原生API的公开`TableStep`枚举增加`FlattenRows`、`SplitColumnPadded`、`PivotRecordLists`。下游若穷举匹配该枚举，需要增加分支或适当的通配分支；这属于源码兼容性变化，因此使用次版本号升级。JSON兼容不等于所有原生源码无须修改。

`synthesize_table`增加可选`intent`参数；旧调用方式保留。JSON请求新增`intent`，并拒绝未知字段，以便尽早暴露拼写错误。`flatten_all`只检查明确的整批展平，不执行通用搜索。

旧`split_column`与`pivot_records`的严格错误行为保留。可选字段需明确使用`split_column_padded`；重复值列表需明确使用`pivot_record_lists`。JSON数组字符串中，缺失为`[]`，真实空字符串为`[""]`；两者不会混合。
