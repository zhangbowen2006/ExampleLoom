# JSON protocol, row recipe v1 and table pipeline v2

The exported `handle(request: String) -> String` always returns JSON. Ordinary input failures are `{ "ok": false, "error": "..." }`. There is no network, filesystem or host-code execution in this boundary.

## Parse

```json
{"op":"parse","format":"csv","text":"code\n订单-0012\n订单-0081\n"}
```

Success: `{ "ok": true, "table": { "columns": ["code"], "rows": [["订单-0012"],["订单-0081"]] } }`. Format can also be `jsonl`.

## Synthesize

```json
{"op":"synthesize","examples":[{"input":["订单-0012"],"output":"0012"},{"input":["订单-0081"],"output":"0081"}],"rows":[["订单-123456"]],"options":{"max_candidates":64}}
```

Success contains ordered `candidates` (expression, description, cost), `disagreements` (zero-based row_index, split score and outcome groups), `stats`, `status` and `truncated`. Options may override max_candidates, max_parts, max_atom_evaluations, max_steps and max_frontier within documented bounds. `exhausted_observed_grammar` refers only to the observed finite search grammar, never the universe of programs. Other statuses mark resource limits. Multiple limits may occur; the status is the most recently encountered reason and truncated remains true.

Optional top-level `separators: ["来自"]` adds up to 16 nonempty separators, each at most 16 Unicode scalar values. Punctuation separators are inferred from every example. Example sorting/deduplication makes label order deterministic. v0.2 stats add `cached_states` and `cache_hits`; `steps` counts path expansions and uncached atom advances, so it is not directly comparable to v0.1.

## Validate and apply

```json
{"op":"validate_recipe","recipe":{"version":1,"columns":["code"],"outputs":[{"name":"id","expression":["token",["field",0],"-",-1]}]}}
```

```json
{"op":"apply","recipe":{"version":1,"columns":["code"],"outputs":[{"name":"id","expression":["token",["field",0],"-",-1]}]},"table":{"columns":["code"],"rows":[["订单-0012"],["订单-123456"]]}}
```

Apply returns output column names, indexed `rows` (each with `ok` and `values` or `error`), failures count and CSV. CSV is null if any row fails. `spreadsheet_safe` defaults true. No partial CSV is silently emitted.

## Expression encoding

| Operator | Encoding |
| --- | --- |
| Column | `["field",0]` |
| Constant | `["literal"," / "]` |
| Trim/case | `["trim",expr]`, `["lower",expr]`, `["upper",expr]` |
| Token | `["token",expr,"-",-1]` |
| ASCII run | `["run",expr,"digits",0]` or `"letters"` |
| Character slice | `["slice",expr,["start",1],["end",0]]` |
| Calendar | `["date",expr,"YYYYMMDD","YYYY-MM-DD"]` |
| Concatenation | `["concat",[expr1,expr2]]` |

The interpreter supports nested expressions; the synthesizer searches the narrower grammar described in ARCHITECTURE.md. An expression accepted by the interpreter is not necessarily learnable. Import rejects unsupported versions, unknown recipe fields/operators, wrong arity, invalid positions and excess depth/nodes.

## v0.3 conditions and regex

Synthesize accepts `patterns:["ref=([[:digit:]]+)"]` (up to 16 MoonBit regex patterns) and `branch_depth:0..3` (default 2). Conditions are fallback induction after flat search has no solution; each partition requires at least two observations. Budgets are shared, and `bounded_branch_search` reports incomplete search. See ARCHITECTURE.md for the narrower learned language and resource limits.

| Expression / predicate | Encoding |
| --- | --- |
| Conditional expression | `["if",condition,yesExpr,noExpr]` |
| Regex capture | `["capture",expr,pattern,group,occurrence]` |
| Global regex replacement | `["replace",expr,pattern,"$2:$1:$$"]` |
| Equality predicate | `["equals",expr1,expr2]` |
| Empty string predicate | `["empty",expr]` |
| Regex predicate | `["matches",expr,pattern,fullMatchBoolean]` |
| Boolean predicates | `["not",condition]`, `["all",[conditions]]`, `["any",[conditions]]` |

If/All/Any short circuit. Capture occurrence may be negative (from the last non-overlapping match). Regex syntax is MoonBit core/lexmatch, not JS/PCRE. Regex replacement is executable but not automatically learned. Old recipes remain readable; older engine versions reject new operators.

## Table synthesis

```json
{"op":"synthesize_table","examples":[{"input":{"columns":["id","Jan","Feb"],"rows":[["A","1","2"]]},"output":{"columns":["id","month","value"],"rows":[["A","Jan","1"],["A","Feb","2"]]}}],"options":{"max_depth":4,"max_states":128,"max_evaluations":2000,"max_candidates":8}}
```

Success contains `candidates:[{"pipeline":...,"description":[steps]}]`, `status`, `truncated`, and `stats:{states,evaluations,rejected,row_searches}`. Empty candidates mean no solution within this grammar/budget, not impossibility. `examples` accepts 1–8 complete input/output table pairs with consistent input schemas (output schemas may differ in v0.4); synthesis limits are lower than execution limits. Optional `separators` overrides the finite structural separator list; `patterns` supplies row-mapping regex hints. No holdout or expected-test-output field exists in the learner.

```json
{"op":"transform","pipeline":{"version":2,"columns":["id","Jan","Feb"],"steps":[["unpivot",["id"],["Jan","Feb"],"month","value"]]},"table":{"columns":["Feb","id","Jan"],"rows":[["9","B","007"]]}}
```

Success contains `table` and `csv`; any failed step returns `ok:false`, with no partial output. `spreadsheet_safe` defaults true. `validate_pipeline` accepts the `pipeline` field and checks format and static parameter validity; data-dependent constraints need actual execution. Input names are rebound before running steps; extra incoming columns are ignored, missing saved names are errors.

| Table operator | Step encoding |
| --- | --- |
| Project/reorder/rename | `["select",[sourceNames],[outputNames]]` |
| Row predicate | `["filter",condition]` |
| Row expressions | `["map_rows",rowRecipeV1]` |
| Split a cell into columns | `["split_column",column,literalSeparator,[newNames]]` |
| Explode into rows | `["explode",column,literalSeparator]` |
| Wide to long | `["unpivot",[keys],[valueColumns],variableName,valueName]` |
| Wide values to long, no variable column | `["fold",[keys],[valueColumns],valueName]` |
| Raw first-row labels to long | `["melt",[keys],[valueColumns],variableName,valueName,skipEmptyBoolean]` |
| Long to wide | `["pivot",[keys],variableColumn,valueColumn,[declaredLevels]]` |
| Consecutive rows to records | `["pack_rows",blockSize,columnwiseBoolean]` |
| Group values into padded records | `["group_rows",[keys],[valueColumns]]` |
| Transpose data cells | `["transpose"]` |
| Header promotion/demotion | `["promote_headers"]`, `["demote_headers"]` |
| Fill empty cells from preceding rows | `["fill_down",[columns]]` |
| Stable first-row-per-key deduplication | `["deduplicate",[keys]]` |
| Drop leading rows | `["drop_rows",count]` |

All cells remain strings. Transpose/PackRows/GroupRows/DemoteHeaders produce generated `c0..` names. Pivot is a closed-schema reshape; it rejects duplicate key-level cells rather than aggregating. GroupRows preserves duplicate values and pads uneven groups with empty strings. PackRows rejects an incomplete trailing block. No SQL join, arbitrary aggregation or unrestricted script is implied.


## v0.4 extensions

`synthesize_table.candidates[]` adds a numeric `cost`, ordered by a declared simplicity prior. It is not confidence. The same input schemas are required across training pairs; output widths/names may differ for dynamic transforms. This can disambiguate a whole-table transpose from fixed-size record packing.

| Operator | Encoding |
| --- | --- |
| Dynamic pivot with labels in first data row | `["pivot_grid",[keys],variableColumn,valueColumn]` |
| Combine selected columns | `["combine_columns",[sourceNames],separator,newName]` |
| Variable-size records | `["segment_rows",predicate,startsRecordBoolean]` |
| Carry header context into detail rows | `["carry_context",headerPredicate,[contextColumns]]` |

`select` now permits repeated source names with distinct output names. Output names must remain unique. Dynamic pivot accepts blank data labels and produces a new schema from observed categories; closed-schema `pivot` retains its previous unknown-level error behavior. Neither operator implicitly aggregates duplicate cells.

Flat synthesis also tries shared literal regex contexts and a finite literal-separator normalization grammar. Arbitrary regex and replacement synthesis remain unsupported. Table macro witnesses charge the normal primitive/depth budgets and do not inspect testing tables or expected test answers.
